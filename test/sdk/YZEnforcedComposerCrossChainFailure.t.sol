// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {YZEnforcedComposer} from "../../src/sdk/YZEnforcedComposer.sol";
import "./YZEnforcedComposerBase.t.sol";

/**
 * @title YZEnforcedComposer Cross-Chain Failure Tests
 * @notice Professional tests for cross-chain failure scenarios and edge cases
 * @dev Simulates LayerZero failures, compose failures, and cross-chain edge cases
 */
contract YZEnforcedComposerCrossChainFailureTest is YZEnforcedComposerBase {
    
    // Test constants
    uint256 internal constant TEST_AMOUNT = 50 ether;
    uint256 internal constant GAS_LIMIT_LOW = 50000;
    uint256 internal constant GAS_LIMIT_HIGH = 1000000;

    function setUp() public override {
        super.setUp();
        _setupDefaultCaps();
    }

    /*//////////////////////////////////////////////////////////////
                        COMPOSE FAILURE SIMULATION
    //////////////////////////////////////////////////////////////*/

    function test_ComposeFailure_SimulatedComposeRevert() public {
        // Setup caps
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        // Simulate compose failure by calling with insufficient gas
        _fundLocalFromHub(userA, TEST_AMOUNT);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), TEST_AMOUNT);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, TEST_AMOUNT);
        
        // Try with very low gas limit to simulate compose failure
        vm.prank(userA);
        vm.expectRevert(); // Should revert due to gas limit or compose failure
        (bool success, ) = address(yzEnforcedComposer_arb).call{gas: GAS_LIMIT_LOW}(
            abi.encodeWithSignature(
                "depositAndSend(uint256,SendParam,address)",
                TEST_AMOUNT,
                sendParam,
                userA
            )
        );
        
        // Verify state is not corrupted
        _assertNoStateChange();
    }

    function test_ComposeFailure_DestinationRevert() public {
        // Setup scenario where destination might revert
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        // Use a non-standard destination address that might cause issues
        address problematicDestination = address(0x1234567890123456789012345678901234567890);
        
        _fundLocalFromHub(userA, TEST_AMOUNT);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), TEST_AMOUNT);
        
        SendParam memory sendParam = _buildHopParam(address(0), problematicDestination, ARB_EID, TEST_AMOUNT);
        
        // Should handle destination issues gracefully
        vm.prank(userA);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend(TEST_AMOUNT, sendParam, userA);
        
        // Verify state is not corrupted
        _assertNoStateChange();
    }

    function test_ComposeFailure_InsufficientLayerZeroFees() public {
        // Setup scenario with insufficient fees
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        _fundLocalFromHub(userA, TEST_AMOUNT);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), TEST_AMOUNT);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, TEST_AMOUNT);
        
        // Call without sending ETH for LayerZero fees
        vm.prank(userA);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend{value: 0}(TEST_AMOUNT, sendParam, userA);
        
        // Verify state is not corrupted
        _assertNoStateChange();
    }

    /*//////////////////////////////////////////////////////////////
                        GAS LIMIT EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_GasLimit_VeryLowGasLimit() public {
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        _fundLocalFromHub(userA, TEST_AMOUNT);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), TEST_AMOUNT);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, TEST_AMOUNT);
        
        // Test with gas limit below minimum required
        vm.prank(userA);
        vm.expectRevert();
        (bool success, ) = address(yzEnforcedComposer_arb).call{gas: 20000}(
            abi.encodeWithSignature(
                "depositAndSend(uint256,SendParam,address)",
                TEST_AMOUNT,
                sendParam,
                userA
            )
        );
        
        _assertNoStateChange();
    }

    function test_GasLimit_VeryHighGasLimit() public {
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        _fundLocalFromHub(userA, TEST_AMOUNT);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), TEST_AMOUNT);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, TEST_AMOUNT);
        
        // Test with very high gas limit (should work)
        vm.prank(userA);
        (bool success, ) = address(yzEnforcedComposer_arb).call{gas: GAS_LIMIT_HIGH}(
            abi.encodeWithSignature(
                "depositAndSend(uint256,SendParam,address)",
                TEST_AMOUNT,
                sendParam,
                userA
            )
        );
        
        // Should succeed with high gas
        assertTrue(success, "High gas limit should work");
        _assertDepositSuccess(userA, TEST_AMOUNT, TEST_AMOUNT);
    }

    function test_GasLimit_GasLimitManipulationAttack() public {
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        // Try various gas limits to see if any bypass enforcement
        uint256[] memory gasLimits = new uint256[](5);
        gasLimits[0] = 21000;      // Minimum
        gasLimits[1] = 50000;      // Low
        gasLimits[2] = 100000;     // Medium
        gasLimits[3] = 500000;     // High
        gasLimits[4] = 1000000;    // Very high
        
        for (uint256 i = 0; i < gasLimits.length; i++) {
            // Reset state
            _resetState();
            
            _fundLocalFromHub(userA, TEST_AMOUNT);
            vm.prank(userA);
            assetOFT_arb.approve(address(yzEnforcedComposer_arb), TEST_AMOUNT);
            
            SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, TEST_AMOUNT);
            
            vm.prank(userA);
            (bool success, ) = address(yzEnforcedComposer_arb).call{gas: gasLimits[i]}(
                abi.encodeWithSignature(
                    "depositAndSend(uint256,SendParam,address)",
                    TEST_AMOUNT,
                    sendParam,
                    userA
                )
            );
            
            // Should either succeed or fail gracefully, but not bypass enforcement
            if (success) {
                _assertDepositSuccess(userA, TEST_AMOUNT, TEST_AMOUNT);
            } else {
                _assertNoStateChange();
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                        CROSS-CHAIN EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_CrossChain_DifferentChainDeposits() public {
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        // Deposit from ETH chain
        _fundLocalFromHub(userA, TEST_AMOUNT);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), TEST_AMOUNT);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ETH_EID, TEST_AMOUNT);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(TEST_AMOUNT, sendParam, userA);
        
        uint256 tvlAfterETH = vault_arb.totalAssets();
        assertEq(tvlAfterETH, TEST_AMOUNT);
        
        // Deposit from POL chain
        _fundLocalFromHub(userB, TEST_AMOUNT);
        vm.prank(userB);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), TEST_AMOUNT);
        
        sendParam = _buildHopParam(address(0), userB, POL_EID, TEST_AMOUNT);
        
        vm.prank(userB);
        yzEnforcedComposer_arb.depositAndSend(TEST_AMOUNT, sendParam, userB);
        
        uint256 tvlAfterPOL = vault_arb.totalAssets();
        assertEq(tvlAfterPOL, TEST_AMOUNT * 2);
        
        // Try to exceed TVL cap from ARB chain
        _fundLocalFromHub(userC, TEST_AMOUNT);
        vm.prank(userC);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), TEST_AMOUNT);
        
        sendParam = _buildHopParam(address(0), userC, ARB_EID, TEST_AMOUNT);
        
        vm.prank(userC);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend(TEST_AMOUNT, sendParam, userC);
        
        // Verify TVL cap enforced across all chains
        assertEq(vault_arb.totalAssets(), TEST_AMOUNT * 2);
    }

    function test_CrossChain_UserTrackingAcrossChains() public {
        _setupUserCap(userA, 100 ether);
        
        // User deposits from ETH chain
        _fundLocalFromHub(userA, 50 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ETH_EID, 50 ether);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(50 ether, sendParam, userA);
        
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), 50 ether);
        
        // User tries to deposit more from POL chain (should be tracked)
        _fundLocalFromHub(userA, 60 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 60 ether);
        
        sendParam = _buildHopParam(address(0), userA, POL_EID, 60 ether);
        
        vm.prank(userA);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend(60 ether, sendParam, userA);
        
        // Verify user cap enforced across chains
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), 50 ether);
    }

    function test_CrossChain_WhitelistEnforcementAcrossChains() public {
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelistEnabled(true);
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelist(userA, true);
        
        // Whitelisted user deposits from ETH
        _fundLocalFromHub(userA, TEST_AMOUNT);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), TEST_AMOUNT);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ETH_EID, TEST_AMOUNT);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(TEST_AMOUNT, sendParam, userA);
        
        assertEq(vault_arb.totalAssets(), TEST_AMOUNT);
        
        // Non-whitelisted user tries from POL
        _fundLocalFromHub(userB, TEST_AMOUNT);
        vm.prank(userB);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), TEST_AMOUNT);
        
        sendParam = _buildHopParam(address(0), userB, POL_EID, TEST_AMOUNT);
        
        vm.prank(userB);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend(TEST_AMOUNT, sendParam, userB);
        
        // Verify whitelist enforced across chains
        assertEq(vault_arb.totalAssets(), TEST_AMOUNT);
        assertEq(yzEnforcedComposer_arb.userDeposits(userB), 0);
    }

    function test_CrossChain_PauseEnforcementAcrossChains() public {
        vm.prank(admin);
        yzEnforcedComposer_arb.pauseDeposits();
        
        // Try to deposit from any chain
        address[] memory chains = new address[](3);
        chains[0] = address(uint160(ETH_EID));
        chains[1] = address(uint160(POL_EID));
        chains[2] = address(uint160(ARB_EID));
        
        for (uint256 i = 0; i < chains.length; i++) {
            address griefer = address(uint160(uint256(keccak256(abi.encodePacked("griefer", i)))));
            
            _fundLocalFromHub(griefer, TEST_AMOUNT);
            vm.prank(griefer);
            assetOFT_arb.approve(address(yzEnforcedComposer_arb), TEST_AMOUNT);
            
            uint32 chainEid = uint32(uint160(chains[i]));
            SendParam memory sendParam = _buildHopParam(address(0), griefer, chainEid, TEST_AMOUNT);
            
            vm.prank(griefer);
            vm.expectRevert();
            yzEnforcedComposer_arb.depositAndSend(TEST_AMOUNT, sendParam, griefer);
        }
        
        // Verify pause enforced across all chains
        assertEq(vault_arb.totalAssets(), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        LAYERZERO FAILURE SIMULATION
    //////////////////////////////////////////////////////////////*/

    function test_LayerZero_FeeInsufficiency() public {
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        _fundLocalFromHub(userA, TEST_AMOUNT);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), TEST_AMOUNT);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, TEST_AMOUNT);
        
        // Send insufficient ETH for LayerZero fees
        uint256 insufficientFee = 0.0001 ether;
        
        vm.prank(userA);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend{value: insufficientFee}(TEST_AMOUNT, sendParam, userA);
        
        _assertNoStateChange();
    }

    function test_LayerZero_InvalidDestinationChain() public {
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        _fundLocalFromHub(userA, TEST_AMOUNT);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), TEST_AMOUNT);
        
        // Use invalid chain ID
        uint32 invalidChainId = 999999;
        SendParam memory sendParam = _buildHopParam(address(0), userA, invalidChainId, TEST_AMOUNT);
        
        vm.prank(userA);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend(TEST_AMOUNT, sendParam, userA);
        
        _assertNoStateChange();
    }

    function test_LayerZero_MessageSizeLimit() public {
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        // Test with very large amount that might exceed message size
        uint256 largeAmount = type(uint256).max;
        
        _fundLocalFromHub(userA, largeAmount);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), largeAmount);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, largeAmount);
        
        vm.prank(userA);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend(largeAmount, sendParam, userA);
        
        _assertNoStateChange();
    }

    /*//////////////////////////////////////////////////////////////
                        REDEMPTION FAILURE SIMULATION
    //////////////////////////////////////////////////////////////*/

    function test_RedemptionFailure_InsufficientShares() public {
        uint256 redeemAmount = 100 ether;
        
        vm.prank(userA);
        vault_arb.approve(address(yzEnforcedComposer_arb), redeemAmount);
        
        SendParam memory redeemParam = _buildHopParam(address(0), userA, ARB_EID, redeemAmount);
        
        vm.prank(userA);
        vm.expectRevert();
        yzEnforcedComposer_arb.redeemAndSend(redeemAmount, redeemParam, userA);
        
        _assertNoStateChange();
    }

    function test_RedemptionFailure_RedemptionsPaused() public {
        uint256 initialDeposit = 50 ether;
        _executeSuccessfulDeposit(userA, initialDeposit);
        
        vm.prank(admin);
        yzEnforcedComposer_arb.pauseRedemptions();
        
        uint256 redeemAmount = 25 ether;
        vm.prank(userA);
        vault_arb.approve(address(yzEnforcedComposer_arb), redeemAmount);
        
        SendParam memory redeemParam = _buildHopParam(address(0), userA, ARB_EID, redeemAmount);
        
        vm.expectRevert(YZEnforcedComposer.YZ_RedemptionsPaused.selector);
        vm.prank(userA);
        yzEnforcedComposer_arb.redeemAndSend(redeemAmount, redeemParam, userA);
        
        _assertRedeemNoStateChange(userA, initialDeposit);
    }

    function test_RedemptionFailure_InsufficientLayerZeroFees() public {
        uint256 initialDeposit = 50 ether;
        _executeSuccessfulDeposit(userA, initialDeposit);
        
        uint256 redeemAmount = 25 ether;
        vm.prank(userA);
        vault_arb.approve(address(yzEnforcedComposer_arb), redeemAmount);
        
        SendParam memory redeemParam = _buildHopParam(address(0), userA, ARB_EID, redeemAmount);
        
        // Call without sending ETH for LayerZero fees
        vm.prank(userA);
        vm.expectRevert();
        yzEnforcedComposer_arb.redeemAndSend{value: 0}(redeemAmount, redeemParam, userA);
        
        _assertRedeemNoStateChange(userA, initialDeposit);
    }

    /*//////////////////////////////////////////////////////////////
                            HELPERS
    //////////////////////////////////////////////////////////////*/

    function _setupDefaultCaps() internal {
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(MAX_TEST_AMOUNT);
    }

    function _setupUserCap(address user, uint256 cap) internal {
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(user, cap);
    }

    function _setupTVLCap(uint256 cap) internal {
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(cap);
    }

    function _executeSuccessfulDeposit(address user, uint256 amount) internal {
        _fundLocalFromHub(user, amount);
        vm.prank(user);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), amount);
        
        SendParam memory sendParam = _buildHopParam(address(0), user, ARB_EID, amount);
        
        vm.prank(user);
        yzEnforcedComposer_arb.depositAndSend(amount, sendParam, user);
    }

    function _assertDepositSuccess(address user, uint256 depositAmount, uint256 expectedTVLIncrease) internal {
        assertEq(vault_arb.totalAssets(), expectedTVLIncrease);
        assertEq(yzEnforcedComposer_arb.userDeposits(user), depositAmount);
    }

    function _assertRedeemSuccess(address user, uint256 initialDeposit, uint256 redeemAmount) internal {
        uint256 expectedRemaining = initialDeposit - redeemAmount;
        assertEq(yzEnforcedComposer_arb.userDeposits(user), expectedRemaining);
    }

    function _assertRedeemNoStateChange(address user, uint256 initialDeposit) internal {
        assertEq(yzEnforcedComposer_arb.userDeposits(user), initialDeposit);
        assertEq(vault_arb.totalAssets(), initialDeposit);
    }

    function _assertNoStateChange() internal {
        assertEq(vault_arb.totalAssets(), 0);
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), 0);
    }

    function _resetState() internal {
        // Reset contract state for next test iteration
        // This would typically involve resetting storage, but in Foundry
        // we usually just start fresh for each test
        vm.clearMockedCalls();
    }
}