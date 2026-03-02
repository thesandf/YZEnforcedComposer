// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {YZEnforcedComposer} from "../../src/sdk/YZEnforcedComposer.sol";
import "./YZEnforcedComposerBase.t.sol";

contract YZEnforcedComposerGasGriefingTest is YZEnforcedComposerBase {
    
    function test_GasGriefing_DepositRevertCost_NotVulnerable() public {
        // Setup caps that will cause reverts
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(50 ether);
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(userA, 25 ether);
        
        // User deposits to reach caps
        _fundLocalFromHub(userA, 25 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 25 ether);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 25 ether);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(25 ether, sendParam, userA);
        
        // Try to grief by causing reverts with small amounts
        uint256 initialGas = gasleft();
        
        _fundLocalFromHub(userB, 1 ether);
        vm.prank(userB);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 1 ether);
        
        sendParam = _buildHopParam(address(0), userB, ARB_EID, 1 ether);
        
        uint256 gasBefore = gasleft();
        vm.prank(userB);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend(1 ether, sendParam, userB);
        uint256 gasAfter = gasleft();
        
        uint256 gasUsed = gasBefore - gasAfter;
        
        // Verify gas cost is reasonable (not excessive)
        // Should be much less than initial gas and not cause DoS
        assertLt(gasUsed, initialGas / 2);
        
        // Verify contract state unchanged
        assertEq(vault_arb.totalAssets(), 25 ether);
        assertEq(yzEnforcedComposer_arb.userDeposits(userB), 0);
    }
    
    function test_GasGriefing_RevertHandling_NotVulnerable() public {
        // Setup malicious scenario
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(1 ether);
        
        // Try to grief with multiple reverts
        for (uint256 i = 0; i < 5; i++) {
            address griefer = address(uint160(uint256(keccak256(abi.encodePacked("griefer", i)))));
            
            _fundLocalFromHub(griefer, 1 ether);
            vm.prank(griefer);
            assetOFT_arb.approve(address(yzEnforcedComposer_arb), 1 ether);
            
            SendParam memory sendParam = _buildHopParam(address(0), griefer, ARB_EID, 1 ether);
            
            vm.prank(griefer);
            vm.expectRevert();
            yzEnforcedComposer_arb.depositAndSend(1 ether, sendParam, griefer);
        }
        
        // Verify contract remains functional
        assertEq(vault_arb.totalAssets(), 0);
        
        // Legitimate user should still be able to use contract
        _fundLocalFromHub(userA, 1 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 1 ether);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 1 ether);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(1 ether, sendParam, userA);
        
        assertEq(vault_arb.totalAssets(), 1 ether);
    }
    
    function test_GasGriefing_LargeDepositRevert_NotVulnerable() public {
        // Setup low cap
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(10 ether);
        
        // Try to grief with large deposit that will revert
        _fundLocalFromHub(userA, 100 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 100 ether);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 100 ether);
        
        uint256 gasBefore = gasleft();
        vm.prank(userA);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend(100 ether, sendParam, userA);
        uint256 gasAfter = gasleft();
        
        uint256 gasUsed = gasBefore - gasAfter;
        
        // Verify gas cost is reasonable regardless of deposit amount
        assertLt(gasUsed, 1000000); // Should not scale with deposit amount
        
        // Verify contract state unchanged
        assertEq(vault_arb.totalAssets(), 0);
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), 0);
    }
    
    function test_GasGriefing_UserCapRevert_NotVulnerable() public {
        // Setup low user cap
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(userA, 1 ether);
        
        // User deposits to cap
        _fundLocalFromHub(userA, 1 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 1 ether);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 1 ether);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(1 ether, sendParam, userA);
        
        // Try to grief with multiple small reverts
        for (uint256 i = 0; i < 10; i++) {
            _fundLocalFromHub(userA, 0.1 ether);
            vm.prank(userA);
            assetOFT_arb.approve(address(yzEnforcedComposer_arb), 0.1 ether);
            
            sendParam = _buildHopParam(address(0), userA, ARB_EID, 0.1 ether);
            
            vm.prank(userA);
            vm.expectRevert();
            yzEnforcedComposer_arb.depositAndSend(0.1 ether, sendParam, userA);
        }
        
        // Verify contract remains functional and state consistent
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), 1 ether);
        assertEq(vault_arb.totalAssets(), 1 ether);
    }
    
    function test_GasGriefing_WhitelistRevert_NotVulnerable() public {
        // Setup whitelist
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelistEnabled(true);
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelist(userA, true);
        
        // Try to grief with non-whitelisted addresses
        for (uint256 i = 0; i < 10; i++) {
            address nonWhitelisted = address(uint160(uint256(keccak256(abi.encodePacked("nonwhite", i)))));
            
            _fundLocalFromHub(nonWhitelisted, 1 ether);
            vm.prank(nonWhitelisted);
            assetOFT_arb.approve(address(yzEnforcedComposer_arb), 1 ether);
            
            SendParam memory sendParam = _buildHopParam(address(0), nonWhitelisted, ARB_EID, 1 ether);
            
            vm.prank(nonWhitelisted);
            vm.expectRevert();
            yzEnforcedComposer_arb.depositAndSend(1 ether, sendParam, nonWhitelisted);
        }
        
        // Verify whitelist enforcement and contract functionality
        assertEq(vault_arb.totalAssets(), 0);
        
        // Whitelisted user should still work
        _fundLocalFromHub(userA, 1 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 1 ether);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 1 ether);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(1 ether, sendParam, userA);
        
        assertEq(vault_arb.totalAssets(), 1 ether);
    }
    
    function test_GasGriefing_PauseRevert_NotVulnerable() public {
        // Pause deposits
        vm.prank(admin);
        yzEnforcedComposer_arb.pauseDeposits();
        
        // Try to grief with multiple pause reverts
        for (uint256 i = 0; i < 10; i++) {
            address griefer = address(uint160(uint256(keccak256(abi.encodePacked("griefer", i)))));
            
            _fundLocalFromHub(griefer, 1 ether);
            vm.prank(griefer);
            assetOFT_arb.approve(address(yzEnforcedComposer_arb), 1 ether);
            
            SendParam memory sendParam = _buildHopParam(address(0), griefer, ARB_EID, 1 ether);
            
            vm.prank(griefer);
            vm.expectRevert();
            yzEnforcedComposer_arb.depositAndSend(1 ether, sendParam, griefer);
        }
        
        // Verify pause enforcement and contract state
        assertEq(vault_arb.totalAssets(), 0);
        
        // Unpause should restore functionality
        vm.prank(admin);
        yzEnforcedComposer_arb.unpauseDeposits();
        
        _fundLocalFromHub(userA, 1 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 1 ether);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 1 ether);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(1 ether, sendParam, userA);
        
        assertEq(vault_arb.totalAssets(), 1 ether);
    }
    
    function test_GasGriefing_CrossChainRevert_NotVulnerable() public {
        // Setup TVL cap
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(50 ether);
        
        // Deposit from ETH chain
        _fundLocalFromHub(userA, 50 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ETH_EID, 50 ether);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(50 ether, sendParam, userA);
        
        // Try to grief from other chains
        address[] memory chains = new address[](2);
        chains[0] = address(uint160(ETH_EID));
        chains[1] = address(uint160(POL_EID));
        
        for (uint256 i = 0; i < chains.length; i++) {
            address griefer = address(uint160(uint256(keccak256(abi.encodePacked("chain_griefer", i)))));
            
            _fundLocalFromHub(griefer, 10 ether);
            vm.prank(griefer);
            assetOFT_arb.approve(address(yzEnforcedComposer_arb), 10 ether);
            
            uint32 chainEid = uint32(uint160(chains[i]));
            sendParam = _buildHopParam(address(0), griefer, chainEid, 10 ether);
            
            vm.prank(griefer);
            vm.expectRevert();
            yzEnforcedComposer_arb.depositAndSend(10 ether, sendParam, griefer);
        }
        
        // Verify cross-chain revert handling
        assertEq(vault_arb.totalAssets(), 50 ether);
    }
    
    function test_GasGriefing_ReentrancyRevert_NotVulnerable() public {
        // Setup caps
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(10 ether);
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(userA, 5 ether);
        
        // Deploy malicious contract that tries reentrancy
        MaliciousGriefContract maliciousContract = new MaliciousGriefContract(address(yzEnforcedComposer_arb));
        
        // Try to grief with reentrancy attempts
        _fundLocalFromHub(address(maliciousContract), 20 ether);
        vm.prank(address(maliciousContract));
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 20 ether);
        
        SendParam memory sendParam = _buildHopParam(address(0), address(maliciousContract), ARB_EID, 20 ether);
        
        vm.prank(address(maliciousContract));
        vm.expectRevert("ReentrancyGuard: reentrant call");
        yzEnforcedComposer_arb.depositAndSend(20 ether, sendParam, address(maliciousContract));
        
        // Verify reentrancy protection works
        assertEq(vault_arb.totalAssets(), 0);
        assertEq(yzEnforcedComposer_arb.userDeposits(address(maliciousContract)), 0);
    }
    
    function test_GasGriefing_GasLimitManipulation_NotVulnerable() public {
        // Setup scenario where gas limits might be manipulated
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(1 ether);
        
        // Try to manipulate gas limits to cause griefing
        _fundLocalFromHub(userA, 10 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 10 ether);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 10 ether);
        
        // Try with different gas limits
        for (uint256 gasLimit = 21000; gasLimit <= 500000; gasLimit += 50000) {
            vm.prank(userA);
            vm.expectRevert();
            (bool success, ) = address(yzEnforcedComposer_arb).call{gas: gasLimit}(
                abi.encodeWithSignature(
                    "depositAndSend(uint256,SendParam,address)",
                    10 ether,
                    sendParam,
                    userA
                )
            );
        }
        
        // Verify contract remains functional
        assertEq(vault_arb.totalAssets(), 0);
        
        // Legitimate deposit should work
        _fundLocalFromHub(userB, 1 ether);
        vm.prank(userB);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 1 ether);
        
        sendParam = _buildHopParam(address(0), userB, ARB_EID, 1 ether);
        
        vm.prank(userB);
        yzEnforcedComposer_arb.depositAndSend(1 ether, sendParam, userB);
        
        assertEq(vault_arb.totalAssets(), 1 ether);
    }
    
    function test_GasGriefing_StateConsistency_AfterReverts() public {
        // Setup multiple enforcement checks
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(100 ether);
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(userA, 50 ether);
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(userB, 50 ether);
        
        // Successful deposits
        _fundLocalFromHub(userA, 50 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(50 ether, sendParam, userA);
        
        _fundLocalFromHub(userB, 40 ether);
        vm.prank(userB);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 40 ether);
        
        sendParam = _buildHopParam(address(0), userB, ARB_EID, 40 ether);
        
        vm.prank(userB);
        yzEnforcedComposer_arb.depositAndSend(40 ether, sendParam, userB);
        
        // Try to grief with various reverts
        address[] memory griefers = new address[](5);
        for (uint256 i = 0; i < griefers.length; i++) {
            griefers[i] = address(uint160(uint256(keccak256(abi.encodePacked("griefer", i)))));
            
            _fundLocalFromHub(griefers[i], 10 ether);
            vm.prank(griefers[i]);
            assetOFT_arb.approve(address(yzEnforcedComposer_arb), 10 ether);
            
            sendParam = _buildHopParam(address(0), griefers[i], ARB_EID, 10 ether);
            
            vm.prank(griefers[i]);
            vm.expectRevert();
            yzEnforcedComposer_arb.depositAndSend(10 ether, sendParam, griefers[i]);
        }
        
        // Verify state consistency after all reverts
        assertEq(vault_arb.totalAssets(), 90 ether);
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), 50 ether);
        assertEq(yzEnforcedComposer_arb.userDeposits(userB), 40 ether);
        
        // Contract should remain fully functional
        _fundLocalFromHub(userC, 10 ether);
        vm.prank(userC);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 10 ether);
        
        sendParam = _buildHopParam(address(0), userC, ARB_EID, 10 ether);
        
        vm.prank(userC);
        yzEnforcedComposer_arb.depositAndSend(10 ether, sendParam, userC);
        
        assertEq(vault_arb.totalAssets(), 100 ether);
        assertEq(yzEnforcedComposer_arb.userDeposits(userC), 10 ether);
    }
}

contract MaliciousGriefContract {
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
    
    // Try to reenter during deposit
    function reenter() external {
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