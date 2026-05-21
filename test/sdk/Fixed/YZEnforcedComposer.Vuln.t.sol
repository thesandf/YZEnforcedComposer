// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

import {YZEnforcedComposer} from "../../src/sdk/YZEnforcedComposer.sol";

import "./YZEnforcedComposerBase.t.sol";

contract YZEnforcedComposerVulnTests is YZEnforcedComposerBase {
    uint256 internal constant TVL_CAP = 1000 ether;

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
    // VULNERABILITY REPRODUCTION TESTS
    // These tests PASS on the vulnerable contract
    // =========================================================

    function test_Vuln_SlippageCheckUsesPreTruncationAmount() public {
        uint256 amount = 100 ether;

        _depositViaComposer(userA, amount);

        vm.prank(userA);
        vault_arb.approve(address(yzEnforcedComposer_arb), amount);

        /*
            Vulnerable flow:

            _assertSlippage(assetAmountReceived, minAmountLD)

            happens BEFORE OFT decimal truncation.

            So slippage validation succeeds even though
            downstream OFT transfer delivers less.
        */

        SendParam memory redeemParam = _buildHopParam(address(0), userA, ETH_EID, amount);

        redeemParam.minAmountLD = amount;

        vm.prank(userA);

        // Vulnerable contract incorrectly succeeds
        yzEnforcedComposer_arb.redeemAndSend(amount, redeemParam, userA);
    }

    function test_Vuln_UserCapResetAfterYieldRedemption() public {
        uint256 depositAmount = 100 ether;
        uint256 yieldAmount = 20 ether;

        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(userA, depositAmount);

        _depositViaComposer(userA, depositAmount);

        assertEq(yzEnforcedComposer_arb.userShares(userA), depositAmount);

        /*
            Simulate vault yield.

            Vulnerable accounting tracks ASSETS instead of SHARES.
        */
        _mintVaultYield(yieldAmount);

        uint256 userShares = vault_arb.balanceOf(userA);

        vm.prank(userA);
        vault_arb.approve(address(yzEnforcedComposer_arb), userShares);

        uint256 expectedAssets = vault_arb.previewRedeem(userShares);

        SendParam memory redeemParam = _buildHopParam(address(0), userA, ARB_EID, expectedAssets);

        redeemParam.minAmountLD = 1;

        vm.prank(userA);
        yzEnforcedComposer_arb.redeemAndSend(userShares, redeemParam, userA);

        /*
            Vulnerable behavior:

            userShares gets reset to 0 because
            redemption assets exceed tracked deposit.
        */
        assertEq(yzEnforcedComposer_arb.userShares(userA), 0);

        /*
            User can now fully redeposit despite already
            consuming cap previously.
        */
        _fundLocalFromHub(userA, depositAmount);

        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), depositAmount);

        SendParam memory p = _buildHopParam(address(0), userA, ARB_EID, depositAmount);

        vm.prank(userA);

        // Vulnerable contract incorrectly allows redeposit
        yzEnforcedComposer_arb.depositAndSend(depositAmount, p, userA);
    }

    function test_Vuln_BatchSetUserCapsAllowsZeroAddress() public {
        address[] memory users = new address[](1);
        users[0] = address(0);

        uint256[] memory caps = new uint256[](1);
        caps[0] = 50 ether;

        vm.prank(admin);

        // Vulnerable contract incorrectly succeeds
        yzEnforcedComposer_arb.batchSetUserCaps(users, caps);

        assertEq(yzEnforcedComposer_arb.userDepositCap(address(0)), 50 ether);
    }

    function test_Vuln_BatchSetWhitelistAllowsZeroAddress() public {
        address[] memory users = new address[](1);
        users[0] = address(0);

        bool[] memory statuses = new bool[](1);
        statuses[0] = true;

        vm.prank(admin);

        // Vulnerable contract incorrectly succeeds
        yzEnforcedComposer_arb.batchSetWhitelist(users, statuses);

        assertTrue(yzEnforcedComposer_arb.whitelist(address(0)));
    }

    function test_Vuln_EmergencyWithdrawNativeMissingEvent() public {
        vm.deal(address(yzEnforcedComposer_arb), 2 ether);

        vm.recordLogs();

        vm.prank(admin);

        yzEnforcedComposer_arb.emergencyWithdrawNative(1 ether, payable(recipient));

        Vm.Log[] memory entries = vm.getRecordedLogs();

        bytes32 eventSig = keccak256("EmergencyWithdrawNative(address,uint256)");

        bool found;

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics.length > 0 && entries[i].topics[0] == eventSig) {
                found = true;
            }
        }

        // Vulnerable contract emits no event
        assertFalse(found);

        assertEq(recipient.balance, 1 ether);
    }

function test_Vuln_CanDepositAllowsDepositThatActuallyExceedsCap() public {
    uint256 initialDeposit = 100 ether;
    uint256 userCap = 101 ether;

    vm.prank(admin);
    yzEnforcedComposer_arb.setUserCap(userA, userCap);

    // Initial deposit
    _depositViaComposer(userA, initialDeposit);

    /*
        Burn vault assets.

        Share price decreases.

        Now:
            1 asset > 1 share

        canDeposit() still checks using raw assets,
        so it incorrectly allows the deposit.
    */

    vm.prank(address(vault_arb));
    assetOFT_arb.transfer(address(0xdead), 50 ether);

    // canDeposit incorrectly allows
    (bool allowed,) =
        yzEnforcedComposer_arb.canDeposit(userA, 1 ether);

    assertTrue(allowed);

    // Actual deposit exceeds share cap
    _fundLocalFromHub(userA, 1 ether);

    vm.prank(userA);
    assetOFT_arb.approve(address(yzEnforcedComposer_arb), 1 ether);

    SendParam memory p =
        _buildHopParam(address(0), userA, ARB_EID, 1 ether);

    vm.prank(userA);

    vm.expectRevert(
        abi.encodeWithSelector(
            YZEnforcedComposer.YZ_UserCapExceeded.selector,
            userA,
            100 ether,
            1999999999999999999,
            101 ether
        )
    );

    yzEnforcedComposer_arb.depositAndSend(1 ether, p, userA);
}
}
