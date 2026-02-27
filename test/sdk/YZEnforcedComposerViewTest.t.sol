// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {YZEnforcedComposer} from "../../src/sdk/YZEnforcedComposer.sol";
import "./YZEnforcedComposerBase.t.sol";

contract YZEnforcedComposerViewTest is YZEnforcedComposerBase {
    
    function test_GetTotalValueLocked_ReturnsVaultTVL() public view {
        uint256 tvl = yzEnforcedComposer_arb.getTotalValueLocked();
        assertEq(tvl, 0);
    }
    
    function test_GetUserShares_ReturnsCorrectBalance() public view {
        uint256 shares = yzEnforcedComposer_arb.getUserShares(userA);
        assertEq(shares, 0);
    }
    
    function test_GetUserDepositInfo_ReturnsCorrectInfo() public {
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(userA, 100 ether);
        
        vm.prank(admin);
        yzEnforcedComposer_arb.exposed_setUserDeposit(userA, 30 ether);
        
        (uint256 deposit, uint256 cap, uint256 remaining) = yzEnforcedComposer_arb.getUserDepositInfo(userA);
        
        assertEq(deposit, 30 ether);
        assertEq(cap, 100 ether);
        assertEq(remaining, 70 ether);
    }
    
    function test_GetUserDepositInfo_ZeroCap_ReturnsMaxRemaining() public view {
        (, , uint256 remaining) = yzEnforcedComposer_arb.getUserDepositInfo(userA);
        assertEq(remaining, type(uint256).max);
    }
    
    function test_CanDeposit_ReturnsTrueWhenNoRestrictions() public view {
        (bool allowed, string memory reason) = yzEnforcedComposer_arb.canDeposit(userA, 10 ether);
        assertTrue(allowed);
        assertEq(reason, "");
    }
    
    function test_CanDeposit_ReturnsFalseWhenDepositsPaused() public {
        vm.prank(admin);
        yzEnforcedComposer_arb.pauseDeposits();
        
        (bool allowed, string memory reason) = yzEnforcedComposer_arb.canDeposit(userA, 10 ether);
        assertFalse(allowed);
        assertEq(reason, "Deposits paused");
    }
    
    function test_CanDeposit_ReturnsFalseWhenNotWhitelisted() public {
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelistEnabled(true);
        
        (bool allowed, string memory reason) = yzEnforcedComposer_arb.canDeposit(userA, 10 ether);
        assertFalse(allowed);
        assertEq(reason, "Not whitelisted");
    }
    
    function test_CanDeposit_ReturnsTrueWhenWhitelisted() public {
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelistEnabled(true);
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelist(userA, true);
        
        (bool allowed, ) = yzEnforcedComposer_arb.canDeposit(userA, 10 ether);
        assertTrue(allowed);
    }
    
    function test_CanDeposit_ReturnsFalseWhenTVLCapExceeded() public {
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(50 ether);
        
        (bool allowed, string memory reason) = yzEnforcedComposer_arb.canDeposit(userA, 100 ether);
        assertFalse(allowed);
        assertEq(reason, "TVL cap exceeded");
    }
    
    function test_CanDeposit_ReturnsTrueWhenAllowed() public {
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(100 ether);
        
        (bool allowed, string memory reason) = yzEnforcedComposer_arb.canDeposit(userA, 50 ether);
        assertTrue(allowed);
        assertEq(reason, "");
    }
    
    function test_CanDeposit_ReturnsFalseWhenUserCapExceeded() public {
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(userA, 50 ether);
        
        (bool allowed, string memory reason) = yzEnforcedComposer_arb.canDeposit(userA, 100 ether);
        assertFalse(allowed);
        assertEq(reason, "User cap exceeded");
    }
}