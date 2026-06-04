// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {YZEnforcedComposer} from "../../src/YZEnforcedComposer.sol";
import "./YZEnforcedComposerBase.t.sol";

contract YZEnforcedComposerTVLCapTest is YZEnforcedComposerBase {
    function test_SetTVLCap_UpdatesCap() public {
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit YZEnforcedComposer.TVLCapUpdated(0, 100 ether);
        yzEnforcedComposer_arb.setTVLCap(100 ether);

        assertEq(yzEnforcedComposer_arb.tvlCap(), 100 ether);
    }

    function test_SetTVLCap_CanSetToZero() public {
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(100 ether);

        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(0);

        assertEq(yzEnforcedComposer_arb.tvlCap(), 0);
    }

    function test_Deposit_RevertsWhenTVLCapExceeded() public {
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(50 ether);

        _fundLocalFromHub(userA, 60 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 60 ether);

        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 60 ether);

        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSelector(YZEnforcedComposer.YZ_TVLCapExceeded.selector, 0, 60 ether, 50 ether));
        yzEnforcedComposer_arb.depositAndSend(60 ether, sendParam, userA);
    }

    function test_Deposit_SucceedsWhenWithinTVLCap() public {
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(100 ether);

        _fundLocalFromHub(userA, 50 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);

        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);

        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(50 ether, sendParam, userA);

        assertEq(vault_arb.totalAssets(), 50 ether);
    }

    function test_Deposit_TVLCapZeroMeansUnlimited() public {
        assertEq(yzEnforcedComposer_arb.tvlCap(), 0);

        _fundLocalFromHub(userA, 1000 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 1000 ether);

        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 1000 ether);

        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(1000 ether, sendParam, userA);

        assertEq(vault_arb.totalAssets(), 1000 ether);
    }

    function test_Deposit_ExactTVLCapBoundary_Succeeds() public {
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(100 ether);

        _fundLocalFromHub(userA, 100 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 100 ether);

        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 100 ether);

        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(100 ether, sendParam, userA);

        assertEq(vault_arb.totalAssets(), 100 ether);
    }

    function test_Deposit_TVLCapExceededByOneWei_Reverts() public {
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(100 ether);

        uint256 depositAmount = 100 ether + 1;

        _fundLocalFromHub(userA, depositAmount);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), depositAmount);

        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, depositAmount);

        vm.prank(userA);
        vm.expectRevert(
            abi.encodeWithSelector(YZEnforcedComposer.YZ_TVLCapExceeded.selector, 0, depositAmount, 100 ether)
        );
        yzEnforcedComposer_arb.depositAndSend(depositAmount, sendParam, userA);
    }

    function testFuzz_SetTVLCap(uint256 _cap) public {
        vm.assume(_cap < type(uint256).max / 2);
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(_cap);
        assertEq(yzEnforcedComposer_arb.tvlCap(), _cap);
    }

    function testFuzz_Deposit_NeverExceedsTVLCap(uint256 _amount) public {
        _amount = bound(_amount, 1, 100 ether);

        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(50 ether);

        _fundLocalFromHub(userA, _amount);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), _amount);

        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, _amount);

        vm.prank(userA);
        if (_amount > 50 ether) {
            vm.expectRevert();
        }
        yzEnforcedComposer_arb.depositAndSend(_amount, sendParam, userA);

        if (_amount <= 50 ether) {
            assertLe(vault_arb.totalAssets(), 50 ether);
        }
    }
}
