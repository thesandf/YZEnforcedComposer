// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {YZEnforcedComposer} from "../../src/sdk/YZEnforcedComposer.sol";
import "./YZEnforcedComposerBase.t.sol";

contract YZEnforcedComposerPauseTest is YZEnforcedComposerBase {
    
    function test_PauseDeposits_SetsDepositsPaused() public {
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit YZEnforcedComposer.DepositsPaused(admin);
        yzEnforcedComposer_arb.pauseDeposits();
        
        assertTrue(yzEnforcedComposer_arb.depositsPaused());
        assertFalse(yzEnforcedComposer_arb.redemptionsPaused());
    }
    
    function test_UnpauseDeposits_ClearsDepositsPaused() public {
        vm.prank(admin);
        yzEnforcedComposer_arb.pauseDeposits();
        
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit YZEnforcedComposer.DepositsUnpaused(admin);
        yzEnforcedComposer_arb.unpauseDeposits();
        
        assertFalse(yzEnforcedComposer_arb.depositsPaused());
    }
    
    function test_PauseRedemptions_SetsRedemptionsPaused() public {
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit YZEnforcedComposer.RedemptionsPaused(admin);
        yzEnforcedComposer_arb.pauseRedemptions();
        
        assertTrue(yzEnforcedComposer_arb.redemptionsPaused());
        assertFalse(yzEnforcedComposer_arb.depositsPaused());
    }
    
    function test_UnpauseRedemptions_ClearsRedemptionsPaused() public {
        vm.prank(admin);
        yzEnforcedComposer_arb.pauseRedemptions();
        
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit YZEnforcedComposer.RedemptionsUnpaused(admin);
        yzEnforcedComposer_arb.unpauseRedemptions();
        
        assertFalse(yzEnforcedComposer_arb.redemptionsPaused());
    }
    
    function test_PauseAll_SetsBothPaused() public {
        vm.prank(admin);
        yzEnforcedComposer_arb.pauseAll();
        
        assertTrue(yzEnforcedComposer_arb.depositsPaused());
        assertTrue(yzEnforcedComposer_arb.redemptionsPaused());
    }
    
    function test_UnpauseAll_ClearsBothPaused() public {
        vm.prank(admin);
        yzEnforcedComposer_arb.pauseAll();
        
        vm.prank(admin);
        yzEnforcedComposer_arb.unpauseAll();
        
        assertFalse(yzEnforcedComposer_arb.depositsPaused());
        assertFalse(yzEnforcedComposer_arb.redemptionsPaused());
    }
    
    function test_Deposit_RevertsWhenDepositsPaused() public {
        vm.prank(admin);
        yzEnforcedComposer_arb.pauseDeposits();
        
        _fundLocalFromHub(userA, 50 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);
        
        vm.prank(userA);
        vm.expectRevert(YZEnforcedComposer.YZ_DepositsPaused.selector);
        yzEnforcedComposer_arb.depositAndSend(50 ether, sendParam, userA);
    }
    
    function test_Redeem_RevertsWhenRedemptionsPaused() public {
        _fundLocalFromHub(userA, 50 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);
        
        SendParam memory depositParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(50 ether, depositParam, userA);
        
        vm.prank(admin);
        yzEnforcedComposer_arb.pauseRedemptions();
        
        vm.prank(userA);
        vault_arb.approve(address(yzEnforcedComposer_arb), 50 ether);
        
        SendParam memory redeemParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);
        
        vm.prank(userA);
        vm.expectRevert(YZEnforcedComposer.YZ_RedemptionsPaused.selector);
        yzEnforcedComposer_arb.redeemAndSend(50 ether, redeemParam, userA);
    }
    
    function test_PauseAll_BlocksBoth() public {
        vm.prank(admin);
        yzEnforcedComposer_arb.pauseAll();
        
        assertTrue(yzEnforcedComposer_arb.depositsPaused());
        assertTrue(yzEnforcedComposer_arb.redemptionsPaused());
        
        _fundLocalFromHub(userA, 50 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);
        
        vm.prank(userA);
        vm.expectRevert(YZEnforcedComposer.YZ_DepositsPaused.selector);
        yzEnforcedComposer_arb.depositAndSend(50 ether, sendParam, userA);
    }
    
    function test_UnpauseAll_RestoresOperations() public {
        vm.prank(admin);
        yzEnforcedComposer_arb.pauseAll();
        
        vm.prank(admin);
        yzEnforcedComposer_arb.unpauseAll();
        
        assertFalse(yzEnforcedComposer_arb.depositsPaused());
        assertFalse(yzEnforcedComposer_arb.redemptionsPaused());
        
        _fundLocalFromHub(userA, 50 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(50 ether, sendParam, userA);
        
        assertEq(vault_arb.totalAssets(), 50 ether);
    }
    
    function test_EmergencyShutdown() public {
        vm.prank(admin);
        yzEnforcedComposer_arb.pauseAll();
        
        assertTrue(yzEnforcedComposer_arb.depositsPaused());
        assertTrue(yzEnforcedComposer_arb.redemptionsPaused());
        
        (bool allowed, string memory reason) = yzEnforcedComposer_arb.canDeposit(userA, 10 ether);
        assertFalse(allowed);
        assertEq(reason, "Deposits paused");
        
        vm.prank(admin);
        yzEnforcedComposer_arb.unpauseDeposits();
        
        (allowed, ) = yzEnforcedComposer_arb.canDeposit(userA, 10 ether);
        assertTrue(allowed);
    }
}