// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {YZEnforcedComposer} from "../../src/YZEnforcedComposer.sol";
import "./YZEnforcedComposerBase.t.sol";

contract YZEnforcedComposerEmergencyTest is YZEnforcedComposerBase {
    function test_EmergencyWithdraw_TransfersAssets() public {
        _fundLocalFromHub(address(yzEnforcedComposer_arb), 100 ether);

        vm.prank(admin);
        yzEnforcedComposer_arb.emergencyWithdraw(50 ether, recipient);

        assertEq(assetOFT_arb.balanceOf(recipient), 50 ether);
        assertEq(assetOFT_arb.balanceOf(address(yzEnforcedComposer_arb)), 50 ether);
    }

    function test_EmergencyWithdraw_RevertsOnZeroAddress() public {
        _fundLocalFromHub(address(yzEnforcedComposer_arb), 100 ether);

        vm.prank(admin);
        vm.expectRevert(YZEnforcedComposer.YZ_ZeroAddress.selector);
        yzEnforcedComposer_arb.emergencyWithdraw(50 ether, address(0));
    }

    function test_EmergencyWithdraw_RevertsOnZeroAmount() public {
        _fundLocalFromHub(address(yzEnforcedComposer_arb), 100 ether);

        vm.prank(admin);
        vm.expectRevert(YZEnforcedComposer.YZ_ZeroAmount.selector);
        yzEnforcedComposer_arb.emergencyWithdraw(0, recipient);
    }

    function test_EmergencyWithdraw_RevertsOnInsufficientBalance() public {
        _fundLocalFromHub(address(yzEnforcedComposer_arb), 10 ether);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(YZEnforcedComposer.YZ_InsufficientBalance.selector, 10 ether, 50 ether));
        yzEnforcedComposer_arb.emergencyWithdraw(50 ether, recipient);
    }

    function test_EmergencyWithdrawShares_TransfersShares() public {
        _fundLocalFromHub(address(yzEnforcedComposer_arb), 100 ether);

        vm.prank(address(yzEnforcedComposer_arb));
        assetOFT_arb.approve(address(vault_arb), 100 ether);

        vm.prank(address(yzEnforcedComposer_arb));
        vault_arb.deposit(100 ether, address(yzEnforcedComposer_arb));

        uint256 composerShares = vault_arb.balanceOf(address(yzEnforcedComposer_arb));
        assertGe(composerShares, 50 ether, "Composer should have shares");

        vm.prank(admin);
        yzEnforcedComposer_arb.emergencyWithdrawShares(50 ether, recipient);

        assertEq(vault_arb.balanceOf(recipient), 50 ether, "Recipient should have shares");
    }

    function test_EmergencyWithdrawNative_TransfersETH() public {
        vm.deal(address(yzEnforcedComposer_arb), 10 ether);

        vm.prank(admin);
        yzEnforcedComposer_arb.emergencyWithdrawNative(5 ether, payable(recipient));

        assertEq(recipient.balance, 5 ether);
    }

    function test_EmergencyWithdrawNative_RevertsOnInsufficientBalance() public {
        vm.deal(address(yzEnforcedComposer_arb), 1 ether);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(YZEnforcedComposer.YZ_InsufficientBalance.selector, 1 ether, 5 ether));
        yzEnforcedComposer_arb.emergencyWithdrawNative(5 ether, payable(recipient));
    }

    function testFuzz_EmergencyWithdraw(uint256 _mintAmount, uint256 _withdrawAmount) public {
        _mintAmount = bound(_mintAmount, 1, 1000 ether);
        _withdrawAmount = bound(_withdrawAmount, 1, _mintAmount);

        _fundLocalFromHub(address(yzEnforcedComposer_arb), _mintAmount);

        vm.prank(admin);
        yzEnforcedComposer_arb.emergencyWithdraw(_withdrawAmount, recipient);

        assertEq(assetOFT_arb.balanceOf(recipient), _withdrawAmount);
    }
}
