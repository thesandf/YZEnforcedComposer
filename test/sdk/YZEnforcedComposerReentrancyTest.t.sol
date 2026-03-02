// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {YZEnforcedComposer} from "../../src/sdk/YZEnforcedComposer.sol";
import "./YZEnforcedComposerBase.t.sol";

contract YZEnforcedComposerReentrancyTest is YZEnforcedComposerBase {
    
    // Malicious contract that attempts reentrancy attacks
    MaliciousVault public maliciousVault;
    
    function setUp() public override {
        super.setUp();
        
        // Deploy malicious vault that will try to reenter during deposit/redeem
        maliciousVault = new MaliciousVault(address(yzEnforcedComposer_arb));
    }
    
    function test_Reentrancy_DepositAndSend_NotVulnerable() public {
        _fundLocalFromHub(userA, 100 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 100 ether);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 100 ether);
        
        // Malicious user tries to reenter during deposit
        vm.prank(userA);
        maliciousVault.setReentrancyTarget(address(yzEnforcedComposer_arb), 1);
        
        vm.prank(userA);
        vm.expectRevert("ReentrancyGuard: reentrant call");
        yzEnforcedComposer_arb.depositAndSend(100 ether, sendParam, userA);
        
        // Verify no state corruption
        assertEq(vault_arb.totalAssets(), 0);
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), 0);
    }
    
    function test_Reentrancy_RedeemAndSend_NotVulnerable() public {
        // First deposit normally
        _fundLocalFromHub(userA, 100 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 100 ether);
        
        SendParam memory depositParam = _buildHopParam(address(0), userA, ARB_EID, 100 ether);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(100 ether, depositParam, userA);
        
        // Now try to reenter during redeem
        vm.prank(userA);
        vault_arb.approve(address(yzEnforcedComposer_arb), 50 ether);
        
        SendParam memory redeemParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);
        
        vm.prank(userA);
        maliciousVault.setReentrancyTarget(address(yzEnforcedComposer_arb), 2);
        
        vm.prank(userA);
        vm.expectRevert("ReentrancyGuard: reentrant call");
        yzEnforcedComposer_arb.redeemAndSend(50 ether, redeemParam, userA);
        
        // Verify no state corruption
        assertEq(vault_arb.totalAssets(), 100 ether);
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), 100 ether);
    }
    
    function test_Reentrancy_EnforcementChecks_NotVulnerable() public {
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(100 ether);
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(userA, 50 ether);
        
        // User deposits to reach cap
        _fundLocalFromHub(userA, 50 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(50 ether, sendParam, userA);
        
        // Try to reenter during enforcement check
        _fundLocalFromHub(userA, 10 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 10 ether);
        
        sendParam = _buildHopParam(address(0), userA, ARB_EID, 10 ether);
        
        vm.prank(userA);
        maliciousVault.setReentrancyTarget(address(yzEnforcedComposer_arb), 3);
        
        vm.prank(userA);
        vm.expectRevert("ReentrancyGuard: reentrant call");
        yzEnforcedComposer_arb.depositAndSend(10 ether, sendParam, userA);
        
        // Verify caps still enforced
        assertEq(vault_arb.totalAssets(), 50 ether);
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), 50 ether);
    }
    
    function test_Reentrancy_PauseControls_NotVulnerable() public {
        // Try to reenter during pause/unpause
        vm.prank(userA);
        maliciousVault.setReentrancyTarget(address(yzEnforcedComposer_arb), 4);
        
        vm.prank(userA);
        vm.expectRevert(YZEnforcedComposer.YZ_NotAdmin.selector);
        yzEnforcedComposer_arb.pauseDeposits();
        
        vm.prank(userA);
        vm.expectRevert(YZEnforcedComposer.YZ_NotAdmin.selector);
        yzEnforcedComposer_arb.unpauseDeposits();
    }
    
    function test_Reentrancy_CapUpdates_NotVulnerable() public {
        // Try to reenter during cap updates
        vm.prank(userA);
        maliciousVault.setReentrancyTarget(address(yzEnforcedComposer_arb), 5);
        
        vm.prank(userA);
        vm.expectRevert(YZEnforcedComposer.YZ_NotAdmin.selector);
        yzEnforcedComposer_arb.setTVLCap(200 ether);
        
        vm.prank(userA);
        vm.expectRevert(YZEnforcedComposer.YZ_NotAdmin.selector);
        yzEnforcedComposer_arb.setUserCap(userA, 100 ether);
    }
    
    function test_Reentrancy_WhitelistUpdates_NotVulnerable() public {
        // Try to reenter during whitelist updates
        vm.prank(userA);
        maliciousVault.setReentrancyTarget(address(yzEnforcedComposer_arb), 6);
        
        vm.prank(userA);
        vm.expectRevert(YZEnforcedComposer.YZ_NotAdmin.selector);
        yzEnforcedComposer_arb.setWhitelistEnabled(true);
        
        vm.prank(userA);
        vm.expectRevert(YZEnforcedComposer.YZ_NotAdmin.selector);
        yzEnforcedComposer_arb.setWhitelist(userA, true);
    }
    
    function test_Reentrancy_EmergencyWithdraw_NotVulnerable() public {
        _fundLocalFromHub(address(yzEnforcedComposer_arb), 100 ether);
        
        // Try to reenter during emergency withdraw
        vm.prank(userA);
        maliciousVault.setReentrancyTarget(address(yzEnforcedComposer_arb), 7);
        
        vm.prank(userA);
        vm.expectRevert(YZEnforcedComposer.YZ_NotAdmin.selector);
        yzEnforcedComposer_arb.emergencyWithdraw(50 ether, recipient);
    }
}

contract MaliciousVault {
    YZEnforcedComposer public composer;
    uint256 public reentrancyTarget;
    
    constructor(address _composer) {
        composer = YZEnforcedComposer(_composer);
    }
    
    function setReentrancyTarget(address _target, uint256 _targetFunction) external {
        reentrancyTarget = _targetFunction;
    }
    
    // Fallback to receive ETH for emergency withdraw test
    receive() external payable {}
    
    // Attempt reentrancy during deposit
    function maliciousDeposit() external {
        SendParam memory sendParam = SendParam({
            dstEid: 1,
            to: bytes32(0),
            amountLD: 1 ether,
            minAmountLD: 1 ether,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });
        
        composer.depositAndSend(1 ether, sendParam, address(this));
    }
    
    // Attempt reentrancy during redeem
    function maliciousRedeem() external {
        SendParam memory sendParam = SendParam({
            dstEid: 1,
            to: bytes32(0),
            amountLD: 1 ether,
            minAmountLD: 1 ether,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });
        
        composer.redeemAndSend(1 ether, sendParam, address(this));
    }
    
    // Attempt reentrancy during enforcement
    function maliciousEnforcement() external {
        SendParam memory sendParam = SendParam({
            dstEid: 1,
            to: bytes32(0),
            amountLD: 1 ether,
            minAmountLD: 1 ether,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });
        
        composer.depositAndSend(1 ether, sendParam, address(this));
    }
    
    // Attempt reentrancy during pause
    function maliciousPause() external {
        composer.pauseDeposits();
    }
    
    // Attempt reentrancy during cap update
    function maliciousCapUpdate() external {
        composer.setTVLCap(200 ether);
    }
    
    // Attempt reentrancy during whitelist update
    function maliciousWhitelistUpdate() external {
        composer.setWhitelistEnabled(true);
    }
    
    // Attempt reentrancy during emergency withdraw
    function maliciousEmergencyWithdraw() external {
        composer.emergencyWithdraw(50 ether, payable(address(this)));
    }
}