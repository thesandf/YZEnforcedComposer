// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {YZEnforcedComposer} from "../../src/YZEnforcedComposer.sol";
import "../unit/YZEnforcedComposerBase.t.sol";
import "forge-std/console2.sol";

/**
 * @title YZEnforcedComposer Invariant Tests
 * @notice Professional invariant tests for YZEnforcedComposer
 * @dev Tests mathematical invariants and state consistency
 */
contract YZEnforcedComposerInvariants is YZEnforcedComposerBase {
    // Invariant test constants
    uint256 internal constant MAX_TEST_AMOUNT = 1000 ether;
    uint256 internal constant MIN_TEST_AMOUNT = 1 ether;

    function setUp() public override {
        super.setUp();
        _setupDefaultCaps();
        targetContract(address(yzEnforcedComposer_arb));

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = yzEnforcedComposer_arb.setAdmin.selector;
        selectors[1] = yzEnforcedComposer_arb.proposeAdmin.selector;
        selectors[2] = yzEnforcedComposer_arb.acceptAdmin.selector;

        excludeSelector(FuzzSelector({addr: address(yzEnforcedComposer_arb), selectors: selectors}));
    }

    /*//////////////////////////////////////////////////////////////
                            INVARIANT TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Test that TVL never exceeds the configured cap
     */
    function invariant_TVLNeverExceedsCap() public {
        uint256 currentTVL = vault_arb.totalAssets();
        uint256 tvlCap = yzEnforcedComposer_arb.tvlCap();

        // If cap is 0, it means unlimited
        if (tvlCap > 0) {
            assertLe(currentTVL, tvlCap, "TVL exceeds configured cap");
        }
    }

    /**
     * @notice Test that user deposits never exceed individual caps
     */
    function invariant_UserDepositsNeverExceedCaps() public {
        address[] memory users = _getAllTestUsers();

        for (uint256 i = 0; i < users.length; i++) {
            uint256 userDeposit = yzEnforcedComposer_arb.userDeposits(users[i]);
            uint256 userCap = yzEnforcedComposer_arb.userDepositCap(users[i]);

            // If cap is 0, it means unlimited
            if (userCap > 0) {
                assertLe(userDeposit, userCap, "User deposit exceeds individual cap");
            }
        }
    }

    /**
     * @notice Test that total user deposits equals TVL
     */
    function invariant_TotalUserDepositsEqualsTVL() public {
        address[] memory users = _getAllTestUsers();
        uint256 totalUserDeposits = 0;

        for (uint256 i = 0; i < users.length; i++) {
            totalUserDeposits += yzEnforcedComposer_arb.userDeposits(users[i]);
        }

        uint256 actualTVL = vault_arb.totalAssets();

        // Allow small rounding differences due to ERC4626 precision
        uint256 diff = actualTVL > totalUserDeposits ? actualTVL - totalUserDeposits : totalUserDeposits - actualTVL;

        assertLe(diff, 1 ether, "Total user deposits should equal TVL within rounding");
    }

    /**
     * @notice Test that share supply is consistent with deposits
     */
    function invariant_ShareSupplyConsistentWithDeposits() public {
        uint256 totalShares = vault_arb.totalSupply();
        uint256 totalAssets = vault_arb.totalAssets();

        // If there are shares, there should be corresponding assets
        if (totalShares > 0) {
            assertGt(totalAssets, 0, "Shares exist but no assets");
        }

        // Share price should be reasonable (between 0.5 and 2.0)
        if (totalShares > 0) {
            uint256 sharePrice = vault_arb.convertToAssets(1 ether);
            assertGe(sharePrice, 0.5 ether, "Share price too low");
            assertLe(sharePrice, 2 ether, "Share price too high");
        }
    }

    /**
     * @notice Test that whitelisted users can deposit when whitelist is enabled
     */
    function invariant_WhitelistEnforcement() public {
        if (yzEnforcedComposer_arb.whitelistEnabled()) {
            // Whitelisted users should be able to deposit (if within caps)
            address whitelistedUser = userA;
            vm.prank(admin);
            yzEnforcedComposer_arb.setWhitelist(whitelistedUser, true);

            uint256 depositAmount = 1 ether;
            _fundLocalFromHub(whitelistedUser, depositAmount);
            vm.startPrank(whitelistedUser);
            assetOFT_arb.approve(address(yzEnforcedComposer_arb), depositAmount);

            SendParam memory sendParam = _buildHopParam(address(0), whitelistedUser, ARB_EID, depositAmount);

            // Should not revert due to whitelist (may revert due to other reasons like caps)
            try yzEnforcedComposer_arb.depositAndSend(depositAmount, sendParam, whitelistedUser) {
            // Success - whitelist enforcement working
            }
            catch (bytes memory reason) {
                // Check if revert is due to whitelist safely without abi.decode
                if (reason.length >= 4) {
                    bytes4 selector;
                    assembly {
                        selector := mload(add(reason, 32))
                    }
                    if (selector == YZEnforcedComposer.YZ_NotWhitelisted.selector) {
                        // This should not happen for whitelisted user
                        assertTrue(false, "Whitelisted user rejected by whitelist");
                    }
                }
                // Other reverts are acceptable (caps, etc.)
            }
            vm.stopPrank();
        }
    }

    /**
     * @notice Test that pause controls work correctly
     */
    function invariant_PauseControlsWork() public {
        // Test deposit pause
        if (yzEnforcedComposer_arb.depositsPaused()) {
            uint256 depositAmount = 1 ether;
            _fundLocalFromHub(userA, depositAmount);
            vm.prank(userA);
            assetOFT_arb.approve(address(yzEnforcedComposer_arb), depositAmount);

            SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, depositAmount);

            vm.expectRevert(YZEnforcedComposer.YZ_DepositsPaused.selector);
            vm.prank(userA);
            yzEnforcedComposer_arb.depositAndSend(depositAmount, sendParam, userA);
        }

        // Test redeem pause
        if (yzEnforcedComposer_arb.redemptionsPaused()) {
            uint256 redeemAmount = 1 ether;
            _fundLocalFromHub(address(yzEnforcedComposer_arb), redeemAmount);
            vm.prank(address(yzEnforcedComposer_arb));
            assetOFT_arb.approve(address(vault_arb), redeemAmount);
            vm.prank(address(yzEnforcedComposer_arb));
            vault_arb.deposit(redeemAmount, userA);

            vm.prank(userA);
            vault_arb.approve(address(yzEnforcedComposer_arb), redeemAmount);

            SendParam memory redeemParam = _buildHopParam(address(0), userA, ARB_EID, redeemAmount);

            vm.expectRevert(YZEnforcedComposer.YZ_RedemptionsPaused.selector);
            vm.prank(userA);
            yzEnforcedComposer_arb.redeemAndSend(redeemAmount, redeemParam, userA);
        }
    }

    /**
     * @notice Test that admin controls are properly restricted
     */
    function invariant_AdminControlsRestricted() public {
        address nonAdmin = userA;

        // Test that non-admin cannot set TVL cap
        vm.expectRevert(YZEnforcedComposer.YZ_NotAdmin.selector);
        vm.prank(nonAdmin);
        yzEnforcedComposer_arb.setTVLCap(100 ether);

        // Test that non-admin cannot set user caps
        vm.expectRevert(YZEnforcedComposer.YZ_NotAdmin.selector);
        vm.prank(nonAdmin);
        yzEnforcedComposer_arb.setUserCap(nonAdmin, 100 ether);

        // Test that non-admin cannot pause
        vm.expectRevert(YZEnforcedComposer.YZ_NotAdmin.selector);
        vm.prank(nonAdmin);
        yzEnforcedComposer_arb.pauseDeposits();

        // Test that non-admin cannot set admin
        vm.expectRevert(YZEnforcedComposer.YZ_NotAdmin.selector);
        vm.prank(nonAdmin);
        yzEnforcedComposer_arb.setAdmin(nonAdmin);
    }

    /**
     * @notice Test that emergency functions are admin-only
     */
    function invariant_EmergencyFunctionsAdminOnly() public {
        address nonAdmin = userA;
        uint256 withdrawAmount = 1 ether;

        _fundLocalFromHub(address(yzEnforcedComposer_arb), withdrawAmount);

        // Test emergency withdraw assets
        vm.expectRevert(YZEnforcedComposer.YZ_NotAdmin.selector);
        vm.prank(nonAdmin);
        yzEnforcedComposer_arb.emergencyWithdraw(withdrawAmount, recipient);

        // Test emergency withdraw shares
        vm.expectRevert(YZEnforcedComposer.YZ_NotAdmin.selector);
        vm.prank(nonAdmin);
        yzEnforcedComposer_arb.emergencyWithdrawShares(withdrawAmount, recipient);

        // Test emergency withdraw native
        vm.deal(address(yzEnforcedComposer_arb), withdrawAmount);
        vm.expectRevert(YZEnforcedComposer.YZ_NotAdmin.selector);
        vm.prank(nonAdmin);
        yzEnforcedComposer_arb.emergencyWithdrawNative(withdrawAmount, payable(recipient));
    }

    /**
     * @notice Test that zero address checks work
     */
    function invariant_ZeroAddressChecks() public {
        // Test set user cap with zero address
        vm.expectRevert(YZEnforcedComposer.YZ_ZeroAddress.selector);
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(address(0), 100 ether);

        // Test emergency withdraw with zero address
        uint256 withdrawAmount = 1 ether;
        _fundLocalFromHub(address(yzEnforcedComposer_arb), withdrawAmount);

        vm.expectRevert(YZEnforcedComposer.YZ_ZeroAddress.selector);
        vm.prank(admin);
        yzEnforcedComposer_arb.emergencyWithdraw(withdrawAmount, address(0));

        // Test set admin with zero address
        vm.expectRevert(YZEnforcedComposer.YZ_ZeroAddress.selector);
        vm.prank(admin);
        yzEnforcedComposer_arb.setAdmin(address(0));
    }

    /**
     * @notice Test that batch operations have consistent lengths
     */
    function invariant_BatchOperationsLengthConsistency() public {
        address[] memory users = new address[](2);
        users[0] = userA;
        users[1] = userB;

        uint256[] memory caps = new uint256[](1); // Wrong length
        caps[0] = 100 ether;

        vm.expectRevert(YZEnforcedComposer.YZ_LengthMismatch.selector);
        vm.prank(admin);
        yzEnforcedComposer_arb.batchSetUserCaps(users, caps);

        bool[] memory statuses = new bool[](1); // Wrong length
        statuses[0] = true;

        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelistEnabled(true);

        vm.expectRevert(YZEnforcedComposer.YZ_LengthMismatch.selector);
        vm.prank(admin);
        yzEnforcedComposer_arb.batchSetWhitelist(users, statuses);
    }

    /**
     * @notice Test that view functions return consistent data
     */
    function invariant_ViewFunctionsConsistency() public {
        address testUser = userA;
        uint256 userShares = vault_arb.balanceOf(testUser);
        uint256 userAssets = vault_arb.convertToAssets(userShares);

        // getUserShares should match vault balance
        assertEq(yzEnforcedComposer_arb.getUserShares(testUser), userShares);

        // getUserAssets should match converted assets
        assertEq(yzEnforcedComposer_arb.getUserAssets(testUser), userAssets);

        // getTotalValueLocked should match vault totalAssets
        assertEq(yzEnforcedComposer_arb.getTotalValueLocked(), vault_arb.totalAssets());

        // getUserDepositInfo should be consistent
        (uint256 deposit, uint256 cap, uint256 remaining) = yzEnforcedComposer_arb.getUserDepositInfo(testUser);
        assertEq(deposit, yzEnforcedComposer_arb.userDeposits(testUser));
        assertEq(cap, yzEnforcedComposer_arb.userDepositCap(testUser));

        if (cap > 0) {
            assertEq(remaining, cap - deposit);
        }
    }

    /**
     * @notice Test that canDeposit returns accurate predictions
     */
    function invariant_CanDepositAccuracy() public {
        address testUser = userA;
        uint256 testAmount = 1 ether;

        (bool canDeposit,) = yzEnforcedComposer_arb.canDeposit(testUser, testAmount);

        // Test the prediction by attempting the actual deposit
        _fundLocalFromHub(testUser, testAmount);
        vm.prank(testUser);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), testAmount);

        SendParam memory sendParam = _buildHopParam(address(0), testUser, ARB_EID, testAmount);

        if (canDeposit) {
            // Should succeed
            vm.prank(testUser);
            yzEnforcedComposer_arb.depositAndSend(testAmount, sendParam, testUser);
            _assertDepositSuccess(testUser, testAmount, testAmount);
        } else {
            // Should revert
            vm.expectRevert();
            vm.prank(testUser);
            yzEnforcedComposer_arb.depositAndSend(testAmount, sendParam, testUser);
            _assertNoStateChange();
        }
    }

    /*//////////////////////////////////////////////////////////////
                            HELPERS
    //////////////////////////////////////////////////////////////*/

    function _setupDefaultCaps() internal {
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(MAX_TEST_AMOUNT);
    }

    function _getAllTestUsers() internal pure returns (address[] memory) {
        address[] memory users = new address[](3);
        users[0] = address(0x1111117Dc0Aa98bF00B17465BB1e5Da1b05b36A8); // userA
        users[1] = address(0x2222227Dc0AA98bF00B17465bB1e5Da1b05B36a8); // userB
        users[2] = address(0x3333337Dc0aa98Bf00b17465Bb1E5Da1b05B36a8); // nonAdmin
        return users;
    }

    function _executeSuccessfulDeposit(address user, uint256 amount) internal {
        _fundLocalFromHub(user, amount);
        vm.prank(user);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), amount);

        SendParam memory sendParam = _buildHopParam(address(0), user, ARB_EID, amount);

        vm.prank(user);
        yzEnforcedComposer_arb.depositAndSend(amount, sendParam, user);
    }

    function _assertDepositSuccess(address user, uint256 depositAmount, uint256 expectedTVLIncrease) internal {
        assertEq(vault_arb.totalAssets(), expectedTVLIncrease);
        assertEq(yzEnforcedComposer_arb.userDeposits(user), depositAmount);
    }

    function _assertNoStateChange() internal {
        assertEq(vault_arb.totalAssets(), 0);
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), 0);
    }
}
