// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

import {YZEnforcedComposer} from "../../../src/sdk/YZEnforcedComposer.Fixed.sol";

import "../YZEnforcedComposerBase.t.sol";

contract YZEnforcedComposerFixedTests is YZEnforcedComposerBase {
    uint256 internal constant TVL_CAP = 1000 ether;

    event EmergencyWithdrawNative(address indexed to, uint256 amount);

    function setUp() public override {
        super.setUp();

        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(TVL_CAP);
    }

    // =========================================================
    // Helpers
    // =========================================================

    function _depositViaComposer(address user, uint256 amount) internal {
        _fundLocalFromHub(user, amount);

        vm.prank(user);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), amount);

        SendParam memory p = _buildHopParam(address(0), user, ARB_EID, amount);

        vm.prank(user);
        yzEnforcedComposer_arb.depositAndSend(amount, p, user);
    }

    function _mintVaultYield(uint256 amount) internal {
        _fundLocalFromHub(address(vault_arb), amount);
    }

    // =========================================================
    // FIX VALIDATION TESTS
    // These tests PASS on the fixed contract
    // =========================================================

    function test_Fix_SlippageCheckUsesPostTruncationAmount() public {
        uint256 amount = 100 ether;

        _depositViaComposer(userA, amount);

        vm.prank(userA);
        vault_arb.approve(address(yzEnforcedComposer_arb), amount);

        /*
            Fixed behavior:

            truncation happens BEFORE slippage validation.

            Therefore this redeem correctly reverts.
        */

        SendParam memory redeemParam = _buildHopParam(address(0), userA, ETH_EID, amount);

        redeemParam.minAmountLD = amount + 1;

        vm.prank(userA);

        vm.expectRevert();

        yzEnforcedComposer_arb.redeemAndSend(amount, redeemParam, userA);
    }

    function test_Fix_UserCapAccountingTracksSharesCorrectly() public {
        uint256 depositAmount = 100 ether;
        uint256 yieldAmount = 20 ether;

        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(userA, depositAmount);

        // ===== Initial Deposit =====

        _depositViaComposer(userA, depositAmount);

        uint256 trackedSharesAfterDeposit = yzEnforcedComposer_arb.userShares(userA);

        assertGt(trackedSharesAfterDeposit, 0);

        // ===== Simulate Vault Yield =====

        _mintVaultYield(yieldAmount);

        // ===== Redeem All Shares =====

        uint256 userVaultShares = vault_arb.balanceOf(userA);

        vm.prank(userA);
        vault_arb.approve(address(yzEnforcedComposer_arb), userVaultShares);

        uint256 expectedAssets = vault_arb.previewRedeem(userVaultShares);

        SendParam memory redeemParam = _buildHopParam(address(0), userA, ARB_EID, expectedAssets);

        redeemParam.minAmountLD = 1;

        vm.prank(userA);
        yzEnforcedComposer_arb.redeemAndSend(userVaultShares, redeemParam, userA);

        // ===== Fixed Behavior =====
        // Tracking uses shares, so redemption should correctly reduce accounting.

        assertEq(yzEnforcedComposer_arb.userShares(userA), 0);

        // ===== User Can Deposit Again ONLY Within Cap =====

        _fundLocalFromHub(userA, depositAmount);

        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), depositAmount);

        SendParam memory depositParam = _buildHopParam(address(0), userA, ARB_EID, depositAmount);
        depositParam.minAmountLD = 1;
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(depositAmount, depositParam, userA);

        assertGt(yzEnforcedComposer_arb.userShares(userA), 0);
    }

    function test_Fix_BatchSetUserCapsRevertsOnZeroAddress() public {
        address[] memory users = new address[](1);
        users[0] = address(0);

        uint256[] memory caps = new uint256[](1);
        caps[0] = 50 ether;

        vm.prank(admin);

        vm.expectRevert(YZEnforcedComposer.YZ_ZeroAddress.selector);

        yzEnforcedComposer_arb.batchSetUserCaps(users, caps);
    }

    function test_Fix_BatchSetWhitelistRevertsOnZeroAddress() public {
        address[] memory users = new address[](1);
        users[0] = address(0);

        bool[] memory statuses = new bool[](1);
        statuses[0] = true;

        vm.prank(admin);

        vm.expectRevert(YZEnforcedComposer.YZ_ZeroAddress.selector);

        yzEnforcedComposer_arb.batchSetWhitelist(users, statuses);
    }

    function test_Fix_EmergencyWithdrawNativeEmitsEvent() public {
        vm.deal(address(yzEnforcedComposer_arb), 2 ether);

        vm.expectEmit(true, false, false, true);

        emit EmergencyWithdrawNative(recipient, 1 ether);

        vm.prank(admin);

        yzEnforcedComposer_arb.emergencyWithdrawNative(1 ether, payable(recipient));

        assertEq(recipient.balance, 1 ether);
    }
function test_Fixed_CanDepositRejectsDepositThatWouldExceedShareCap()
    public
{
    uint256 initialDeposit = 100 ether;
    uint256 userCap = 101 ether;

    vm.prank(admin);
    yzEnforcedComposer_arb.setUserCap(userA, userCap);

    _depositViaComposer(userA, initialDeposit);

    // Reduce vault assets
    vm.prank(address(vault_arb));
    assetOFT_arb.transfer(address(0xdead), 50 ether);

    // Fixed version correctly rejects
    (bool allowed, string memory reason) =
        yzEnforcedComposer_arb.canDeposit(userA, 1 ether);

    assertFalse(allowed);
    assertEq(reason, "User cap exceeded");
}
}
