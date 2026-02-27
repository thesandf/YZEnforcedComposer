// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {YZEnforcedComposer} from "../../src/sdk/YZEnforcedComposer.sol";
import "./YZEnforcedComposerBase.t.sol";

contract YZEnforcedComposerWhitelistTest is YZEnforcedComposerBase {
    
    function test_SetWhitelistEnabled_UpdatesState() public {
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit YZEnforcedComposer.WhitelistEnabled(true);
        yzEnforcedComposer_arb.setWhitelistEnabled(true);
        
        assertTrue(yzEnforcedComposer_arb.whitelistEnabled());
    }
    
    function test_SetWhitelist_UpdatesStatus() public {
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit YZEnforcedComposer.WhitelistUpdated(userA, true);
        yzEnforcedComposer_arb.setWhitelist(userA, true);
        
        assertTrue(yzEnforcedComposer_arb.whitelist(userA));
    }
    
    function test_SetWhitelist_RevertsOnZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(YZEnforcedComposer.YZ_ZeroAddress.selector);
        yzEnforcedComposer_arb.setWhitelist(address(0), true);
    }
    
    function test_BatchSetWhitelist_UpdatesMultiple() public {
        address[] memory users = new address[](2);
        users[0] = userA;
        users[1] = userB;
        
        bool[] memory statuses = new bool[](2);
        statuses[0] = true;
        statuses[1] = true;
        
        vm.prank(admin);
        yzEnforcedComposer_arb.batchSetWhitelist(users, statuses);
        
        assertTrue(yzEnforcedComposer_arb.whitelist(userA));
        assertTrue(yzEnforcedComposer_arb.whitelist(userB));
    }
    
    function test_Deposit_RevertsIfWhitelistEnabledAndUserNotWhitelisted() public {
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelistEnabled(true);
        
        _fundLocalFromHub(userA, 50 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);
        
        vm.prank(userA);
        vm.expectRevert(
            abi.encodeWithSelector(
                YZEnforcedComposer.YZ_NotWhitelisted.selector,
                userA
            )
        );
        yzEnforcedComposer_arb.depositAndSend(50 ether, sendParam, userA);
    }
    
    function test_Deposit_SucceedsIfWhitelisted() public {
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelistEnabled(true);
        
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelist(userA, true);
        
        _fundLocalFromHub(userA, 50 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(50 ether, sendParam, userA);
        
        assertEq(vault_arb.totalAssets(), 50 ether);
    }
    
    function test_Deposit_SucceedsIfWhitelistDisabled() public {
        assertFalse(yzEnforcedComposer_arb.whitelistEnabled());
        
        _fundLocalFromHub(userA, 50 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(50 ether, sendParam, userA);
        
        assertEq(vault_arb.totalAssets(), 50 ether);
    }
}