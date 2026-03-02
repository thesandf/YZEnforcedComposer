// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {YZEnforcedComposer} from "../../src/sdk/YZEnforcedComposer.sol";
import "./YZEnforcedComposerBase.t.sol";

contract YZEnforcedComposerRateLimitBypassTest is YZEnforcedComposerBase {
    
    function test_RateLimitBypass_MultipleAddresses_NotVulnerable() public {
        // Setup user cap
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(userA, 100 ether);
        
        // User A deposits to cap
        _fundLocalFromHub(userA, 100 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 100 ether);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 100 ether);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(100 ether, sendParam, userA);
        
        // Try to bypass through multiple addresses controlled by same user
        address controlledAddress1 = address(uint160(uint256(keccak256(abi.encodePacked(userA, 1)))));
        address controlledAddress2 = address(uint160(uint256(keccak256(abi.encodePacked(userA, 2)))));
        
        _fundLocalFromHub(controlledAddress1, 50 ether);
        vm.prank(controlledAddress1);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);
        
        sendParam = _buildHopParam(address(0), controlledAddress1, ARB_EID, 50 ether);
        
        vm.prank(controlledAddress1);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend(50 ether, sendParam, controlledAddress1);
        
        _fundLocalFromHub(controlledAddress2, 50 ether);
        vm.prank(controlledAddress2);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);
        
        sendParam = _buildHopParam(address(0), controlledAddress2, ARB_EID, 50 ether);
        
        vm.prank(controlledAddress2);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend(50 ether, sendParam, controlledAddress2);
        
        // Verify caps still enforced per address
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), 100 ether);
        assertEq(yzEnforcedComposer_arb.userDeposits(controlledAddress1), 0);
        assertEq(yzEnforcedComposer_arb.userDeposits(controlledAddress2), 0);
    }
    
    function test_RateLimitBypass_CrossChainBypass_NotVulnerable() public {
        // Setup TVL cap
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(100 ether);
        
        // Deposit from ETH chain
        _fundLocalFromHub(userA, 50 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ETH_EID, 50 ether);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(50 ether, sendParam, userA);
        
        // Deposit from POL chain
        _fundLocalFromHub(userB, 40 ether);
        vm.prank(userB);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 40 ether);
        
        sendParam = _buildHopParam(address(0), userB, POL_EID, 40 ether);
        
        vm.prank(userB);
        yzEnforcedComposer_arb.depositAndSend(40 ether, sendParam, userB);
        
        // Try to bypass from ARB chain - should be rejected due to TVL cap
        _fundLocalFromHub(userC, 20 ether);
        vm.prank(userC);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 20 ether);
        
        sendParam = _buildHopParam(address(0), userC, ARB_EID, 20 ether);
        
        vm.prank(userC);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend(20 ether, sendParam, userC);
        
        // Verify TVL cap enforced across all chains
        assertEq(vault_arb.totalAssets(), 90 ether);
        assertEq(yzEnforcedComposer_arb.userDeposits(userC), 0);
    }
    
    function test_RateLimitBypass_WhitelistBypass_NotVulnerable() public {
        // Setup whitelist
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelistEnabled(true);
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelist(userA, true);
        
        // User A deposits (whitelisted)
        _fundLocalFromHub(userA, 50 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(50 ether, sendParam, userA);
        
        // Try to bypass through non-whitelisted addresses
        address nonWhitelisted1 = address(uint160(uint256(keccak256(abi.encodePacked(userA, 100)))));
        address nonWhitelisted2 = address(uint160(uint256(keccak256(abi.encodePacked(userA, 200)))));
        
        _fundLocalFromHub(nonWhitelisted1, 30 ether);
        vm.prank(nonWhitelisted1);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 30 ether);
        
        sendParam = _buildHopParam(address(0), nonWhitelisted1, ARB_EID, 30 ether);
        
        vm.prank(nonWhitelisted1);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend(30 ether, sendParam, nonWhitelisted1);
        
        _fundLocalFromHub(nonWhitelisted2, 30 ether);
        vm.prank(nonWhitelisted2);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 30 ether);
        
        sendParam = _buildHopParam(address(0), nonWhitelisted2, ARB_EID, 30 ether);
        
        vm.prank(nonWhitelisted2);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend(30 ether, sendParam, nonWhitelisted2);
        
        // Verify whitelist enforced per address
        assertEq(vault_arb.totalAssets(), 50 ether);
        assertEq(yzEnforcedComposer_arb.userDeposits(nonWhitelisted1), 0);
        assertEq(yzEnforcedComposer_arb.userDeposits(nonWhitelisted2), 0);
    }
    
    function test_RateLimitBypass_PauseBypass_NotVulnerable() public {
        // Pause deposits
        vm.prank(admin);
        yzEnforcedComposer_arb.pauseDeposits();
        
        // Try to bypass through different chains
        _fundLocalFromHub(userA, 50 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ETH_EID, 50 ether);
        
        vm.prank(userA);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend(50 ether, sendParam, userA);
        
        sendParam = _buildHopParam(address(0), userA, POL_EID, 50 ether);
        
        vm.prank(userA);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend(50 ether, sendParam, userA);
        
        sendParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);
        
        vm.prank(userA);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend(50 ether, sendParam, userA);
        
        // Try to bypass through different functions
        vm.prank(userA);
        vm.expectRevert(YZEnforcedComposer.YZ_DepositsPaused.selector);
        yzEnforcedComposer_arb.deposit(50 ether, userA);
        
        // Verify pause enforced across all entry points
        assertEq(vault_arb.totalAssets(), 0);
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), 0);
    }
    
    function test_RateLimitBypass_UserCapManipulation_NotVulnerable() public {
        // Setup user cap
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(userA, 100 ether);
        
        // User deposits to cap
        _fundLocalFromHub(userA, 100 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 100 ether);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 100 ether);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(100 ether, sendParam, userA);
        
        // Try to manipulate user cap through admin functions
        vm.prank(userA);
        vm.expectRevert();
        yzEnforcedComposer_arb.setUserCap(userA, 200 ether); // Should fail - not admin
        
        vm.prank(userA);
        vm.expectRevert();
        yzEnforcedComposer_arb.exposed_setUserDeposit(userA, 50 ether); // Should fail - not admin
        
        // Try to deposit more - should still be rejected
        _fundLocalFromHub(userA, 50 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);
        
        sendParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);
        
        vm.prank(userA);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend(50 ether, sendParam, userA);
        
        // Verify caps integrity
        assertEq(yzEnforcedComposer_arb.userDepositCap(userA), 100 ether);
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), 100 ether);
    }
    
    function test_RateLimitBypass_TVLManipulation_NotVulnerable() public {
        // Setup TVL cap
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(100 ether);
        
        // Deposit to near cap
        _fundLocalFromHub(userA, 90 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 90 ether);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 90 ether);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(90 ether, sendParam, userA);
        
        // Try to manipulate TVL through external calls
        vm.prank(userA);
        vm.expectRevert();
        vault_arb.setTotalAssets(50 ether); // Should fail - only vault controls TVL
        
        // Try to deposit more - should still be rejected
        _fundLocalFromHub(userB, 20 ether);
        vm.prank(userB);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 20 ether);
        
        sendParam = _buildHopParam(address(0), userB, ARB_EID, 20 ether);
        
        vm.prank(userB);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend(20 ether, sendParam, userB);
        
        // Verify TVL integrity
        assertEq(vault_arb.totalAssets(), 90 ether);
        assertEq(yzEnforcedComposer_arb.userDeposits(userB), 0);
    }
    
    function test_RateLimitBypass_ReentrancyBypass_NotVulnerable() public {
        // Setup caps
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(100 ether);
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(userA, 50 ether);
        
        // Deploy malicious contract that tries reentrancy bypass
        MaliciousBypassContract maliciousContract = new MaliciousBypassContract(address(yzEnforcedComposer_arb));
        
        // Try reentrancy attack
        _fundLocalFromHub(address(maliciousContract), 60 ether);
        vm.prank(address(maliciousContract));
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 60 ether);
        
        SendParam memory sendParam = _buildHopParam(address(0), address(maliciousContract), ARB_EID, 60 ether);
        
        vm.prank(address(maliciousContract));
        vm.expectRevert("ReentrancyGuard: reentrant call");
        yzEnforcedComposer_arb.depositAndSend(60 ether, sendParam, address(maliciousContract));
        
        // Verify no bypass occurred
        assertEq(vault_arb.totalAssets(), 0);
        assertEq(yzEnforcedComposer_arb.userDeposits(address(maliciousContract)), 0);
    }
    
    function test_RateLimitBypass_GasLimitBypass_NotVulnerable() public {
        // Setup caps
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(100 ether);
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(userA, 50 ether);
        
        // Try to bypass through gas manipulation
        _fundLocalFromHub(userA, 60 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 60 ether);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 60 ether);
        
        // Try with different gas limits
        vm.prank(userA);
        vm.expectRevert();
        (bool success, ) = address(yzEnforcedComposer_arb).call{gas: 50000}(
            abi.encodeWithSignature(
                "depositAndSend(uint256,SendParam,address)",
                60 ether,
                sendParam,
                userA
            )
        );
        
        vm.prank(userA);
        vm.expectRevert();
        (success, ) = address(yzEnforcedComposer_arb).call{gas: 100000}(
            abi.encodeWithSignature(
                "depositAndSend(uint256,SendParam,address)",
                60 ether,
                sendParam,
                userA
            )
        );
        
        // Verify gas manipulation doesn't bypass enforcement
        assertEq(vault_arb.totalAssets(), 0);
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), 0);
    }
    
    function test_RateLimitBypass_BatchOperations_NotVulnerable() public {
        // Setup caps
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(100 ether);
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(userA, 50 ether);
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(userB, 50 ether);
        
        // Try to bypass through batch operations
        address[] memory users = new address[](2);
        users[0] = userA;
        users[1] = userB;
        
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 60 ether; // Exceeds userA cap
        amounts[1] = 60 ether; // Exceeds userB cap
        
        for (uint256 i = 0; i < users.length; i++) {
            _fundLocalFromHub(users[i], amounts[i]);
            vm.prank(users[i]);
            assetOFT_arb.approve(address(yzEnforcedComposer_arb), amounts[i]);
            
            SendParam memory sendParam = _buildHopParam(address(0), users[i], ARB_EID, amounts[i]);
            
            vm.prank(users[i]);
            vm.expectRevert();
            yzEnforcedComposer_arb.depositAndSend(amounts[i], sendParam, users[i]);
        }
        
        // Verify batch operations don't bypass enforcement
        assertEq(vault_arb.totalAssets(), 0);
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), 0);
        assertEq(yzEnforcedComposer_arb.userDeposits(userB), 0);
    }
    
    function test_RateLimitBypass_TimingAttack_NotVulnerable() public {
        // Setup TVL cap
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(100 ether);
        
        // Multiple users try to deposit simultaneously near cap
        _fundLocalFromHub(userA, 50 ether);
        _fundLocalFromHub(userB, 50 ether);
        _fundLocalFromHub(userC, 50 ether);
        
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);
        vm.prank(userB);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);
        vm.prank(userC);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);
        
        // User A deposits first
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(50 ether, sendParam, userA);
        
        // User B deposits second
        sendParam = _buildHopParam(address(0), userB, ARB_EID, 50 ether);
        
        vm.prank(userB);
        yzEnforcedComposer_arb.depositAndSend(50 ether, sendParam, userB);
        
        // User C tries to deposit - should be rejected due to TVL cap
        sendParam = _buildHopParam(address(0), userC, ARB_EID, 50 ether);
        
        vm.prank(userC);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend(50 ether, sendParam, userC);
        
        // Verify timing attack prevention
        assertEq(vault_arb.totalAssets(), 100 ether);
        assertEq(yzEnforcedComposer_arb.userDeposits(userC), 0);
    }
}

contract MaliciousBypassContract {
    YZEnforcedComposer public composer;
    
    constructor(address _composer) {
        composer = YZEnforcedComposer(_composer);
    }
    
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
    
    // Fallback to receive ETH
    receive() external payable {}
}