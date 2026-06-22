// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../unit/YZEnforcedComposerBase.t.sol";
import {OFTComposeMsgCodec} from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";

contract F2_ShareTransferBypassRegression is YZEnforcedComposerBase {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @notice Verifies that user can deposit again if they transfer their shares away (balance goes below cap)
     */
    function test_CapCannotBeBypassedViaShareTransfer() public {
        uint256 cap = 10 ether;

        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(userA, cap);

        _fundLocalFromHub(userA, cap);

        vm.startPrank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), cap);

        SendParam memory dep = _buildHopParam(address(0), userA, ARB_EID, cap);
        yzEnforcedComposer_arb.depositAndSend(cap, dep, userA);
        vm.stopPrank();

        uint256 shares = vault_arb.balanceOf(userA);
        assertEq(shares, cap);

        // Transfer shares away
        vm.prank(userA);
        vault_arb.transfer(userB, shares);

        assertEq(vault_arb.balanceOf(userA), 0);

        // Try to deposit again under the ownership cap logic
        _fundLocalFromHub(userA, 1 ether);

        vm.startPrank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 1 ether);

        SendParam memory dep2 = _buildHopParam(address(0), userA, ARB_EID, 1 ether);
        yzEnforcedComposer_arb.depositAndSend(1 ether, dep2, userA);
        vm.stopPrank();

        assertGt(vault_arb.balanceOf(userA), 0);
    }

    /**
     * @notice Verifies that receiving shares via transfer consumes the recipient's cap
     */
    function test_ReceivingSharesConsumesCap() public {
        uint256 cap = 5 ether;

        // Set UserB's cap to 5 ether
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(userB, cap);

        // UserA deposits 5 ether
        _fundLocalFromHub(userA, 50 ether);
        vm.startPrank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 5 ether);
        SendParam memory dep = _buildHopParam(address(0), userA, ARB_EID, 5 ether);
        yzEnforcedComposer_arb.depositAndSend(5 ether, dep, userA);
        vm.stopPrank();

        // UserA transfers the 5 ether of shares to UserB
        uint256 shares = vault_arb.balanceOf(userA);
        vm.prank(userA);
        vault_arb.transfer(userB, shares);

        assertEq(vault_arb.balanceOf(userB), 5 ether);

        // UserB attempts to deposit 1 ether, which should fail because they already hold 5 ether of shares (consuming their cap)
        _fundLocalFromHub(userB, 1 ether);
        vm.startPrank(userB);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 1 ether);
        SendParam memory dep2 = _buildHopParam(address(0), userB, ARB_EID, 1 ether);

        vm.expectRevert(); // Should revert due to YZ_UserCapExceeded
        yzEnforcedComposer_arb.depositAndSend(1 ether, dep2, userB);
        vm.stopPrank();
    }

    /**
     * @notice Verifies that yield growth in the vault consumes user cap capacity
     */
    function test_YieldGrowthConsumesOwnershipCap() public {
        uint256 cap = 10 ether;

        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(userA, cap);

        // UserA deposits 9 ether
        _fundLocalFromHub(userA, 9 ether);
        vm.startPrank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 9 ether);
        SendParam memory dep = _buildHopParam(address(0), userA, ARB_EID, 9 ether);
        yzEnforcedComposer_arb.depositAndSend(9 ether, dep, userA);
        vm.stopPrank();

        // Simulate vault yield doubling (assets double while share supply remains same)
        deal(address(assetOFT_arb), address(vault_arb), 18 ether);

        // Current assets value for UserA is now 18 ether, which is > 10 ether cap.
        // UserA's subsequent deposit should be blocked.
        _fundLocalFromHub(userA, 1 ether);
        vm.startPrank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 1 ether);
        SendParam memory dep2 = _buildHopParam(address(0), userA, ARB_EID, 1 ether);

        vm.expectRevert(); // Should revert due to YZ_UserCapExceeded
        yzEnforcedComposer_arb.depositAndSend(1 ether, dep2, userA);
        vm.stopPrank();
    }

    /**
     * @notice Verifies that cap usage updates dynamically on transfer without composer interaction
     */
    function test_CapUsageTracksOwnershipChanges() public {
        uint256 cap = 100 ether;

        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(userB, cap);

        // Verify initial state
        (uint256 ownership, uint256 userCap, uint256 remaining) = yzEnforcedComposer_arb.getUserCapUsage(userB);
        assertEq(ownership, 0);
        assertEq(userCap, cap);
        assertEq(remaining, cap);

        // UserA deposits 100 ether (shares go to UserA locally)
        _fundLocalFromHub(userA, 100 ether);
        vm.startPrank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 100 ether);
        SendParam memory dep = _buildHopParam(address(0), userA, ARB_EID, 100 ether);
        yzEnforcedComposer_arb.depositAndSend(100 ether, dep, userA);
        vm.stopPrank();

        // UserA transfers 40 shares to UserB out-of-band (no composer call)
        vm.prank(userA);
        vault_arb.transfer(userB, 40 ether);

        // Verify UserB's cap usage updated automatically
        (ownership, userCap, remaining) = yzEnforcedComposer_arb.getUserCapUsage(userB);
        assertEq(ownership, 40 ether);
        assertEq(remaining, 60 ether);

        // UserB transfers 10 shares back to UserA
        vm.prank(userB);
        vault_arb.transfer(userA, 10 ether);

        // Verify UserB's cap usage updated automatically to 30 ether
        (ownership, userCap, remaining) = yzEnforcedComposer_arb.getUserCapUsage(userB);
        assertEq(ownership, 30 ether);
        assertEq(remaining, 70 ether);
    }
}
