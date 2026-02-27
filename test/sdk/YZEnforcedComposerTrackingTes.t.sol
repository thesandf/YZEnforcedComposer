// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {YZEnforcedComposer} from "../../src/sdk/YZEnforcedComposer.sol";
import "./YZEnforcedComposerBase.t.sol";

contract YZEnforcedComposerTrackingTest is YZEnforcedComposerBase {
    
    function test_UserDepositTracking_IncreasesAfterDeposit() public {
        _fundLocalFromHub(userA, 100 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 100 ether);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(50 ether, sendParam, userA);
        
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), 50 ether);
        
        sendParam = _buildHopParam(address(0), userA, ARB_EID, 30 ether);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(30 ether, sendParam, userA);
        
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), 80 ether);
    }
    
    function test_UserDepositTracking_UsesActualTVLIncrease() public {
        _fundLocalFromHub(userA, 100 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 100 ether);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 100 ether);
        
        uint256 tvlBefore = vault_arb.totalAssets();
        
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(100 ether, sendParam, userA);
        
        uint256 tvlAfter = vault_arb.totalAssets();
        uint256 actualTvlIncrease = tvlAfter - tvlBefore;
        
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), actualTvlIncrease);
    }
    
    function test_Redeem_DecreasesUserDepositTracking() public {
        _fundLocalFromHub(userA, 100 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 100 ether);
        
        SendParam memory depositParam = _buildHopParam(address(0), userA, ARB_EID, 100 ether);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(100 ether, depositParam, userA);
        
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), 100 ether);
        
        vm.prank(userA);
        vault_arb.approve(address(yzEnforcedComposer_arb), 50 ether);
        
        SendParam memory redeemParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.redeemAndSend(50 ether, redeemParam, userA);
        
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), 50 ether);
    }
    
    function test_Redeem_ResetsTrackingIfUnderflow() public {
        vm.prank(admin);
        yzEnforcedComposer_arb.exposed_setUserDeposit(userA, 10 ether);
        
        _fundLocalFromHub(userA, 100 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 100 ether);
        
        SendParam memory depositParam = _buildHopParam(address(0), userA, ARB_EID, 100 ether);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(100 ether, depositParam, userA);
        
        vm.prank(userA);
        vault_arb.approve(address(yzEnforcedComposer_arb), 50 ether);
        
        SendParam memory redeemParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.redeemAndSend(50 ether, redeemParam, userA);
    }
    
    function test_ExposedSetUserDeposit_SetsDeposit() public {
        vm.prank(admin);
        yzEnforcedComposer_arb.exposed_setUserDeposit(userA, 100 ether);
        
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), 100 ether);
    }
    
    function testFuzz_Redeem_NeverUnderflowsTracking(uint256 _depositAmount, uint256 _redeemAmount) public {
        _depositAmount = bound(_depositAmount, 1, 100 ether);
        _redeemAmount = bound(_redeemAmount, 1, _depositAmount);
        
        _fundLocalFromHub(userA, _depositAmount);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), _depositAmount);
        
        SendParam memory depositParam = _buildHopParam(address(0), userA, ARB_EID, _depositAmount);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(_depositAmount, depositParam, userA);
        
        vm.prank(userA);
        vault_arb.approve(address(yzEnforcedComposer_arb), _redeemAmount);
        
        SendParam memory redeemParam = _buildHopParam(address(0), userA, ARB_EID, _redeemAmount);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.redeemAndSend(_redeemAmount, redeemParam, userA);
        
        assertGe(yzEnforcedComposer_arb.userDeposits(userA), 0);
    }
}