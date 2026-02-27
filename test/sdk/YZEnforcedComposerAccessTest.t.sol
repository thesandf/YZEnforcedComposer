// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {YZEnforcedComposer} from "../../src/sdk/YZEnforcedComposer.sol";
import "./YZEnforcedComposerBase.t.sol";

contract YZEnforcedComposerAccessTest is YZEnforcedComposerBase {
    
    function test_OnlyAdmin_RevertsOnNonAdmin() public {
        vm.prank(nonAdmin);
        vm.expectRevert(YZEnforcedComposer.YZ_NotAdmin.selector);
        yzEnforcedComposer_arb.setTVLCap(100 ether);
    }
    
    function test_OnlyAdmin_AllowsAdmin() public {
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(100 ether);
        assertEq(yzEnforcedComposer_arb.tvlCap(), 100 ether);
    }
    
    function test_SetAdmin_TransfersAdmin() public {
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit YZEnforcedComposer.AdminUpdated(admin, userA);
        yzEnforcedComposer_arb.setAdmin(userA);
        
        assertEq(yzEnforcedComposer_arb.admin(), userA);
    }
    
    function test_SetAdmin_RevertsOnZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(YZEnforcedComposer.YZ_ZeroAddress.selector);
        yzEnforcedComposer_arb.setAdmin(address(0));
    }
    
    function test_SetAdmin_OnlyCurrentAdmin() public {
        vm.prank(nonAdmin);
        vm.expectRevert(YZEnforcedComposer.YZ_NotAdmin.selector);
        yzEnforcedComposer_arb.setAdmin(userA);
    }
    
    function test_AdminTransferWorkflow() public {
        address newAdmin = makeAddr("newAdmin");
        
        // Transfer admin
        vm.prank(admin);
        yzEnforcedComposer_arb.setAdmin(newAdmin);
        
        // Old admin no longer has access
        vm.prank(admin);
        vm.expectRevert(YZEnforcedComposer.YZ_NotAdmin.selector);
        yzEnforcedComposer_arb.setTVLCap(100 ether);
        
        // New admin has access
        vm.prank(newAdmin);
        yzEnforcedComposer_arb.setTVLCap(100 ether);
        
        assertEq(yzEnforcedComposer_arb.tvlCap(), 100 ether);
    }
}