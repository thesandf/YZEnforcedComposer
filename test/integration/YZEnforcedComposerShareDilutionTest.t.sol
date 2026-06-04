// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {YZEnforcedComposer} from "../../src/YZEnforcedComposer.sol";
import "../unit/YZEnforcedComposerBase.t.sol";

contract YZEnforcedComposerShareDilutionTest is YZEnforcedComposerBase {
    function test_ShareDilution_EarlyDepositorProtection() public {
        // User A deposits first
        _fundLocalFromHub(userA, 100 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 100 ether);

        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 100 ether);

        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(100 ether, sendParam, userA);

        uint256 userAShares = vault_arb.balanceOf(userA);
        assertEq(userAShares, 100 ether); // 1:1 initially

        // Simulate strategy yield (TVL increases without new deposits)
        // This would normally dilute early depositors in some systems
        // But ERC4626 handles this correctly through price per share
        uint256 yield = 10 ether;
        _fundLocalFromHub(address(vault_arb), yield);

        // User B deposits after yield
        _fundLocalFromHub(userB, 100 ether);
        vm.prank(userB);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 100 ether);

        sendParam = _buildHopParam(address(0), userB, ARB_EID, 100 ether);
        sendParam.minAmountLD = vault_arb.previewDeposit(100 ether);

        vm.prank(userB);
        yzEnforcedComposer_arb.depositAndSend(100 ether, sendParam, userB);

        uint256 userBShares = vault_arb.balanceOf(userB);

        // Verify no dilution - both users should have fair share based on timing
        uint256 totalAssets = vault_arb.totalAssets();
        uint256 totalShares = vault_arb.totalSupply();

        // User A should have more shares than user B due to earlier deposit
        assertGe(userAShares, userBShares);

        // Verify proportional ownership
        uint256 userAValue = vault_arb.convertToAssets(userAShares);
        uint256 userBValue = vault_arb.convertToAssets(userBShares);

        assertApproxEqAbs(userAValue + userBValue, totalAssets, 1);
    }

    function test_ShareDilution_TVLTracking_Accuracy() public {
        // Multiple users deposit at different times
        _fundLocalFromHub(userA, 50 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);

        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);

        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(50 ether, sendParam, userA);

        _fundLocalFromHub(userB, 30 ether);
        vm.prank(userB);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 30 ether);

        sendParam = _buildHopParam(address(0), userB, ARB_EID, 30 ether);

        vm.prank(userB);
        yzEnforcedComposer_arb.depositAndSend(30 ether, sendParam, userB);

        // Simulate yield
        _fundLocalFromHub(address(vault_arb), 20 ether);

        _fundLocalFromHub(userC, 40 ether);
        vm.prank(userC);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 40 ether);

        sendParam = _buildHopParam(address(0), userC, ARB_EID, 40 ether);
        sendParam.minAmountLD = vault_arb.previewDeposit(40 ether);

        vm.prank(userC);
        yzEnforcedComposer_arb.depositAndSend(40 ether, sendParam, userC);

        // Verify TVL tracking accuracy
        uint256 totalDeposited = 50 ether + 30 ether + 40 ether;
        uint256 totalYield = 20 ether;
        uint256 expectedTVL = totalDeposited + totalYield;

        assertEq(vault_arb.totalAssets(), expectedTVL);

        // Verify user deposit tracking reflects actual contributions
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), 50 ether);
        assertEq(yzEnforcedComposer_arb.userDeposits(userB), 30 ether);
        assertEq(yzEnforcedComposer_arb.userDeposits(userC), 40 ether);
    }

    function test_ShareDilution_RebalanceProtection() public {
        // Setup caps to test rebalance scenarios
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(200 ether);

        // Users deposit to near capacity
        _fundLocalFromHub(userA, 100 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 100 ether);

        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 100 ether);

        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(100 ether, sendParam, userA);

        _fundLocalFromHub(userB, 90 ether);
        vm.prank(userB);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 90 ether);

        sendParam = _buildHopParam(address(0), userB, ARB_EID, 90 ether);

        vm.prank(userB);
        yzEnforcedComposer_arb.depositAndSend(90 ether, sendParam, userB);

        // Simulate yield pushing TVL close to cap
        _fundLocalFromHub(address(vault_arb), 5 ether);

        uint256 tvlBefore = vault_arb.totalAssets();
        assertLe(tvlBefore, 200 ether);

        // Try to deposit more - should be rejected due to TVL cap
        _fundLocalFromHub(userC, 10 ether);
        vm.prank(userC);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 10 ether);

        sendParam = _buildHopParam(address(0), userC, ARB_EID, 10 ether);

        vm.prank(userC);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend(10 ether, sendParam, userC);

        // Verify no dilution through cap bypass
        assertEq(vault_arb.totalAssets(), tvlBefore);
        assertEq(yzEnforcedComposer_arb.userDeposits(userC), 0);
    }

    function test_ShareDilution_WhitelistDilutionPrevention() public {
        // Setup whitelist
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelistEnabled(true);
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelist(userA, true);
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelist(userB, true);

        // Whitelisted users deposit
        _fundLocalFromHub(userA, 50 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);

        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);

        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(50 ether, sendParam, userA);

        _fundLocalFromHub(userB, 50 ether);
        vm.prank(userB);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);

        sendParam = _buildHopParam(address(0), userB, ARB_EID, 50 ether);

        vm.prank(userB);
        yzEnforcedComposer_arb.depositAndSend(50 ether, sendParam, userB);

        // Non-whitelisted user tries to deposit (would cause dilution if allowed)
        _fundLocalFromHub(userC, 30 ether);
        vm.prank(userC);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 30 ether);

        sendParam = _buildHopParam(address(0), userC, ARB_EID, 30 ether);

        vm.prank(userC);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend(30 ether, sendParam, userC);

        // Verify whitelist prevents dilution
        assertEq(vault_arb.totalAssets(), 100 ether);
        assertEq(yzEnforcedComposer_arb.userDeposits(userC), 0);

        // Verify existing users' ownership unchanged
        uint256 userAShares = vault_arb.balanceOf(userA);
        uint256 userBShares = vault_arb.balanceOf(userB);
        assertEq(userAShares, 50 ether);
        assertEq(userBShares, 50 ether);
    }

    function test_ShareDilution_PauseDilutionPrevention() public {
        // Users deposit normally
        _fundLocalFromHub(userA, 100 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 100 ether);

        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 100 ether);

        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(100 ether, sendParam, userA);

        // Pause deposits to prevent dilution
        vm.prank(admin);
        yzEnforcedComposer_arb.pauseDeposits();

        // Try to deposit more - should be rejected
        _fundLocalFromHub(userB, 50 ether);
        vm.prank(userB);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);

        sendParam = _buildHopParam(address(0), userB, ARB_EID, 50 ether);

        vm.prank(userB);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend(50 ether, sendParam, userB);

        // Verify pause prevents dilution
        assertEq(vault_arb.totalAssets(), 100 ether);
        assertEq(yzEnforcedComposer_arb.userDeposits(userB), 0);
        assertEq(vault_arb.balanceOf(userA), 100 ether);
    }

    function test_ShareDilution_UserCapDilutionPrevention() public {
        // Setup user caps
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(userA, 100 ether);
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(userB, 100 ether);

        // User A reaches cap
        _fundLocalFromHub(userA, 100 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 100 ether);

        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 100 ether);

        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(100 ether, sendParam, userA);

        // User B tries to exceed cap
        _fundLocalFromHub(userB, 150 ether);
        vm.prank(userB);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 150 ether);

        sendParam = _buildHopParam(address(0), userB, ARB_EID, 150 ether);

        vm.prank(userB);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend(150 ether, sendParam, userB);

        // Try smaller amount that would still exceed cap
        sendParam = _buildHopParam(address(0), userB, ARB_EID, 110 ether);

        vm.prank(userB);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend(110 ether, sendParam, userB);

        // Try amount within cap
        sendParam = _buildHopParam(address(0), userB, ARB_EID, 100 ether);

        vm.prank(userB);
        yzEnforcedComposer_arb.depositAndSend(100 ether, sendParam, userB);

        // Verify user caps prevent dilution
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), 100 ether);
        assertEq(yzEnforcedComposer_arb.userDeposits(userB), 100 ether);
        assertEq(vault_arb.totalAssets(), 200 ether);
    }

    function test_ShareDilution_CrossChainDilutionPrevention() public {
        // Setup TVL cap
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(150 ether);

        // Deposit from ETH chain
        _fundLocalFromHub(userA, 100 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 100 ether);

        SendParam memory sendParam = _buildHopParam(address(0), userA, ETH_EID, 100 ether);
        uint256 fee = _getAndFundDepositFee(userA, sendParam);

        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend{value: fee}(100 ether, sendParam, userA);

        // Deposit from POL chain
        _fundLocalFromHub(userB, 40 ether);
        vm.prank(userB);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 40 ether);

        sendParam = _buildHopParam(address(0), userB, POL_EID, 40 ether);
        uint256 fee2 = _getAndFundDepositFee(userB, sendParam);

        vm.prank(userB);
        yzEnforcedComposer_arb.depositAndSend{value: fee2}(40 ether, sendParam, userB);

        // Try to deposit from ARB chain - should be rejected due to TVL cap
        _fundLocalFromHub(userC, 20 ether);
        vm.prank(userC);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 20 ether);

        sendParam = _buildHopParam(address(0), userC, ARB_EID, 20 ether);

        vm.prank(userC);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend(20 ether, sendParam, userC);

        // Verify cross-chain dilution prevention
        assertEq(vault_arb.totalAssets(), 140 ether);
        assertEq(yzEnforcedComposer_arb.userDeposits(userC), 0);
    }

    function test_ShareDilution_RedemptionImpact() public {
        // Setup deposits
        _fundLocalFromHub(userA, 100 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 100 ether);

        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 100 ether);

        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(100 ether, sendParam, userA);

        _fundLocalFromHub(userB, 100 ether);
        vm.prank(userB);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 100 ether);

        sendParam = _buildHopParam(address(0), userB, ARB_EID, 100 ether);

        vm.prank(userB);
        yzEnforcedComposer_arb.depositAndSend(100 ether, sendParam, userB);

        // User A redeems
        vm.prank(userA);
        vault_arb.approve(address(yzEnforcedComposer_arb), 50 ether);

        SendParam memory redeemParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);

        vm.prank(userA);
        yzEnforcedComposer_arb.redeemAndSend(50 ether, redeemParam, userA);

        // User C tries to deposit after redemption
        _fundLocalFromHub(userC, 60 ether);
        vm.prank(userC);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 60 ether);

        sendParam = _buildHopParam(address(0), userC, ARB_EID, 60 ether);

        vm.prank(userC);
        yzEnforcedComposer_arb.depositAndSend(60 ether, sendParam, userC);

        // Verify redemption doesn't cause unfair dilution
        uint256 userAShares = vault_arb.balanceOf(userA);
        uint256 userBShares = vault_arb.balanceOf(userB);
        uint256 userCShares = vault_arb.balanceOf(userC);

        // User A should have 50 shares remaining
        assertEq(userAShares, 50 ether);

        // User B should not be diluted by User C's deposit
        assertEq(userBShares, 100 ether);

        // User C should get fair share based on deposit timing
        assertEq(userCShares, 60 ether);
    }

    function test_ShareDilution_StrategyYieldHandling() public {
        // Initial deposit
        _fundLocalFromHub(userA, 100 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 100 ether);

        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 100 ether);

        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(100 ether, sendParam, userA);

        uint256 initialShares = vault_arb.balanceOf(userA);
        uint256 initialTVL = vault_arb.totalAssets();

        // Simulate strategy yield
        uint256 yield = 25 ether;
        _fundLocalFromHub(address(vault_arb), yield);

        uint256 afterYieldTVL = vault_arb.totalAssets();
        uint256 pricePerShare = vault_arb.convertToAssets(1 ether);

        // Verify yield increases TVL and share price
        assertEq(afterYieldTVL, initialTVL + yield);
        assertGt(pricePerShare, 1 ether);

        // New user deposits after yield
        _fundLocalFromHub(userB, 100 ether);
        vm.prank(userB);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 100 ether);

        sendParam = _buildHopParam(address(0), userB, ARB_EID, 100 ether);
        sendParam.minAmountLD = vault_arb.previewDeposit(100 ether);

        vm.prank(userB);
        yzEnforcedComposer_arb.depositAndSend(100 ether, sendParam, userB);

        uint256 userBShares = vault_arb.balanceOf(userB);

        // Verify no unfair dilution - User A's value should reflect yield
        uint256 userAValue = vault_arb.convertToAssets(initialShares);
        uint256 userBValue = vault_arb.convertToAssets(userBShares);

        assertGe(userAValue, initialTVL + yield * 50 / 100); // User A should benefit from yield
        assertApproxEqAbs(userBValue, 100 ether, 1); // User B gets fair value for deposit
    }
}
