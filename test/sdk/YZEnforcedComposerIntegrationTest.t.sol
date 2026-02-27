// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {YZEnforcedComposer} from "../../src/sdk/YZEnforcedComposer.sol";
import "./YZEnforcedComposerBase.t.sol";

contract YZEnforcedComposerIntegrationTest is YZEnforcedComposerBase {
    
    function test_CompleteSetupWorkflow() public {
        // 1. Admin sets up TVL cap
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(1000 ether);
        
        // 2. Admin enables whitelist
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelistEnabled(true);
        
        // 3. Admin adds users to whitelist
        address[] memory users = new address[](2);
        users[0] = userA;
        users[1] = userB;
        
        bool[] memory statuses = new bool[](2);
        statuses[0] = true;
        statuses[1] = true;
        
        vm.prank(admin);
        yzEnforcedComposer_arb.batchSetWhitelist(users, statuses);
        
        // 4. Admin sets individual user caps
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(userA, 100 ether);
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(userB, 200 ether);
        
        // Verify setup
        assertEq(yzEnforcedComposer_arb.tvlCap(), 1000 ether);
        assertTrue(yzEnforcedComposer_arb.whitelistEnabled());
        assertTrue(yzEnforcedComposer_arb.whitelist(userA));
        assertTrue(yzEnforcedComposer_arb.whitelist(userB));
        assertEq(yzEnforcedComposer_arb.userDepositCap(userA), 100 ether);
        assertEq(yzEnforcedComposer_arb.userDepositCap(userB), 200 ether);
        
        // Verify canDeposit checks
        (bool allowedA, ) = yzEnforcedComposer_arb.canDeposit(userA, 50 ether);
        assertTrue(allowedA);
        
        (bool allowedB, ) = yzEnforcedComposer_arb.canDeposit(userB, 150 ether);
        assertTrue(allowedB);
    }
    
    function test_Events_AreEmittedCorrectly() public {
        // TVL Cap
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit YZEnforcedComposer.TVLCapUpdated(0, 100 ether);
        yzEnforcedComposer_arb.setTVLCap(100 ether);
        
        // User Cap
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit YZEnforcedComposer.UserCapUpdated(userA, 0, 50 ether);
        yzEnforcedComposer_arb.setUserCap(userA, 50 ether);
        
        // Admin update
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit YZEnforcedComposer.AdminUpdated(admin, userB);
        yzEnforcedComposer_arb.setAdmin(userB);
    }
    
    function test_FullUserFlow_DepositRedeem() public {
        // Setup caps
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(1000 ether);
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(userA, 500 ether);
        
        // 1. User deposits
        _fundLocalFromHub(userA, 200 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 200 ether);
        
        SendParam memory depositParam = _buildHopParam(address(0), userA, ARB_EID, 200 ether);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(200 ether, depositParam, userA);
        
        assertEq(vault_arb.totalAssets(), 200 ether);
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), 200 ether);
        
        // 2. User redeems half
        vm.prank(userA);
        vault_arb.approve(address(yzEnforcedComposer_arb), 100 ether);
        
        SendParam memory redeemParam = _buildHopParam(address(0), userA, ARB_EID, 100 ether);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.redeemAndSend(100 ether, redeemParam, userA);
        
        assertEq(vault_arb.totalAssets(), 100 ether);
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), 100 ether);
        
        // 3. User deposits again
        _fundLocalFromHub(userA, 50 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);
        
        depositParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(50 ether, depositParam, userA);
        
        assertEq(vault_arb.totalAssets(), 150 ether);
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), 150 ether);
    }
    
    function test_FullUserFlow_MultipleUsers() public {
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(1000 ether);
        
        // User A deposits
        _fundLocalFromHub(userA, 100 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 100 ether);
        
        SendParam memory paramA = _buildHopParam(address(0), userA, ARB_EID, 100 ether);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(100 ether, paramA, userA);
        
        // User B deposits
        _fundLocalFromHub(userB, 200 ether);
        vm.prank(userB);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 200 ether);
        
        SendParam memory paramB = _buildHopParam(address(0), userB, ARB_EID, 200 ether);
        
        vm.prank(userB);
        yzEnforcedComposer_arb.depositAndSend(200 ether, paramB, userB);
        
        // Verify both tracked correctly
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), 100 ether);
        assertEq(yzEnforcedComposer_arb.userDeposits(userB), 200 ether);
        assertEq(vault_arb.totalAssets(), 300 ether);
    }
    
    function test_FullUserFlow_WithEnforcementReverts() public {
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(100 ether);
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(userA, 50 ether);
        
        // 1. Deposit within user cap - succeeds
        _fundLocalFromHub(userA, 50 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);
        
        SendParam memory param = _buildHopParam(address(0), userA, ARB_EID, 50 ether);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(50 ether, param, userA);
        
        // 2. Try to deposit more than user cap - reverts
        _fundLocalFromHub(userA, 30 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 30 ether);
        
        param = _buildHopParam(address(0), userA, ARB_EID, 30 ether);
        
        vm.prank(userA);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend(30 ether, param, userA);
        
        // 3. User B tries to exceed TVL cap - reverts
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(userB, 100 ether);
        
        _fundLocalFromHub(userB, 60 ether);
        vm.prank(userB);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 60 ether);
        
        SendParam memory paramB = _buildHopParam(address(0), userB, ARB_EID, 60 ether);
        
        vm.prank(userB);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend(60 ether, paramB, userB);
    }
}