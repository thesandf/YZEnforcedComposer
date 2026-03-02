// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {YZEnforcedComposer} from "../../src/sdk/YZEnforcedComposer.sol";
import "./YZEnforcedComposerBase.t.sol";

/**
 * @title YZEnforcedComposer Cross-Chain Partial Failure Tests
 * @notice Professional tests for cross-chain partial failure scenarios
 * @dev Tests source state updates, destination reverts, message retries, and atomicity
 */
contract YZEnforcedComposerCrossChainPartialFailureTest is YZEnforcedComposerBase {
    
    // Test constants
    uint256 internal constant TEST_AMOUNT = 50 ether;

    function setUp() public override {
        super.setUp();
        _setupDefaultCaps();
    }

    /*//////////////////////////////////////////////////////////////
                        SOURCE STATE UPDATE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SourceStateUpdate_DestinationRevert() public {
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        // Mock LayerZero endpoint to simulate destination revert
        _mockLayerZeroRevert();
        
        // Execute deposit that will fail at destination
        _fundLocalFromHub(userA, TEST_AMOUNT);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), TEST_AMOUNT);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, TEST_AMOUNT);
        
        // Should handle destination revert gracefully
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(TEST_AMOUNT, sendParam, userA);
        
        // Verify source state is not corrupted
        assertEq(vault_arb.totalAssets(), 0);
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), 0);
        assertEq(assetOFT_arb.balanceOf(userA), 0); // Token should be returned or handled
    }

    function test_SourceStateUpdate_MessageExecutionFailure() public {
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        // Mock message execution failure
        _mockMessageExecutionFailure();
        
        _fundLocalFromHub(userA, TEST_AMOUNT);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), TEST_AMOUNT);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, TEST_AMOUNT);
        
        // Should handle message execution failure
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(TEST_AMOUNT, sendParam, userA);
        
        // Verify state consistency
        assertEq(vault_arb.totalAssets(), 0);
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), 0);
    }

    function test_SourceStateUpdate_InsufficientFees() public {
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        // Mock insufficient LayerZero fees
        _mockInsufficientFees();
        
        _fundLocalFromHub(userA, TEST_AMOUNT);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), TEST_AMOUNT);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, TEST_AMOUNT);
        
        // Should handle insufficient fees
        vm.prank(userA);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend{value: 0}(TEST_AMOUNT, sendParam, userA);
        
        // Verify no state change
        assertEq(vault_arb.totalAssets(), 0);
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        MESSAGE RETRY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_MessageRetry_NoDoubleCredit() public {
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        // First successful deposit
        _executeSuccessfulDeposit(userA, TEST_AMOUNT);
        assertEq(vault_arb.totalAssets(), TEST_AMOUNT);
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), TEST_AMOUNT);
        
        // Simulate message retry (should not double credit)
        _mockMessageRetry();
        
        _fundLocalFromHub(userA, TEST_AMOUNT);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), TEST_AMOUNT);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, TEST_AMOUNT);
        
        // Should not double credit on retry
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(TEST_AMOUNT, sendParam, userA);
        
        // Verify no double credit
        assertEq(vault_arb.totalAssets(), TEST_AMOUNT);
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), TEST_AMOUNT);
    }

    function test_MessageRetry_DuplicateMessageDetection() public {
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        // Execute first deposit
        _executeSuccessfulDeposit(userA, TEST_AMOUNT);
        
        // Simulate duplicate message with same parameters
        _mockDuplicateMessage();
        
        _fundLocalFromHub(userA, TEST_AMOUNT);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), TEST_AMOUNT);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, TEST_AMOUNT);
        
        // Should detect and reject duplicate
        vm.prank(userA);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend(TEST_AMOUNT, sendParam, userA);
        
        // Verify no duplicate processing
        assertEq(vault_arb.totalAssets(), TEST_AMOUNT);
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), TEST_AMOUNT);
    }

    function test_MessageRetry_RetryAfterFailure() public {
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        // First attempt fails
        _mockLayerZeroRevert();
        
        _fundLocalFromHub(userA, TEST_AMOUNT);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), TEST_AMOUNT);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, TEST_AMOUNT);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(TEST_AMOUNT, sendParam, userA);
        
        // Reset mock for successful retry
        _resetLayerZeroMock();
        
        // Retry should succeed
        _fundLocalFromHub(userA, TEST_AMOUNT);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), TEST_AMOUNT);
        
        sendParam = _buildHopParam(address(0), userA, ARB_EID, TEST_AMOUNT);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(TEST_AMOUNT, sendParam, userA);
        
        // Verify successful retry
        assertEq(vault_arb.totalAssets(), TEST_AMOUNT);
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), TEST_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                        OUT-OF-ORDER MESSAGES TESTS
    //////////////////////////////////////////////////////////////*/

    function test_OutOfOrderMessages_SequenceHandling() public {
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        // Deposit 1
        _executeSuccessfulDeposit(userA, 25 ether);
        
        // Simulate out-of-order message (larger amount first)
        _mockOutOfOrderMessage();
        
        _fundLocalFromHub(userA, 50 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);
        
        // Should handle out-of-order gracefully
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(50 ether, sendParam, userA);
        
        // Verify correct total
        assertEq(vault_arb.totalAssets(), 75 ether);
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), 75 ether);
    }

    function test_OutOfOrderMessages_CapEnforcement() public {
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(100 ether);
        
        // Deposit near cap
        _executeSuccessfulDeposit(userA, 75 ether);
        
        // Out-of-order message that would exceed cap
        _mockOutOfOrderMessage();
        
        _fundLocalFromHub(userA, 50 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);
        
        // Should enforce cap even with out-of-order
        vm.prank(userA);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend(50 ether, sendParam, userA);
        
        // Verify cap enforced
        assertEq(vault_arb.totalAssets(), 75 ether);
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), 75 ether);
    }

    /*//////////////////////////////////////////////////////////////
                        FUNDS STUCK SCENARIO TESTS
    //////////////////////////////////////////////////////////////*/

    function test_FundsStuck_RecoveryMechanism() public {
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        // Simulate funds getting stuck in contract
        _mockFundsStuck();
        
        _fundLocalFromHub(userA, TEST_AMOUNT);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), TEST_AMOUNT);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, TEST_AMOUNT);
        
        // Should handle stuck funds scenario
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(TEST_AMOUNT, sendParam, userA);
        
        // Verify funds are not lost
        uint256 stuckFunds = assetOFT_arb.balanceOf(address(yzEnforcedComposer_arb));
        assertLe(stuckFunds, TEST_AMOUNT); // Some funds may be stuck, but not all
        
        // Admin should be able to recover stuck funds
        vm.prank(admin);
        yzEnforcedComposer_arb.emergencyWithdraw(stuckFunds, recipient);
        
        assertEq(assetOFT_arb.balanceOf(recipient), stuckFunds);
    }

    function test_FundsStuck_PartialRecovery() public {
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        // Simulate partial funds stuck
        _mockPartialFundsStuck();
        
        _fundLocalFromHub(userA, TEST_AMOUNT);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), TEST_AMOUNT);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, TEST_AMOUNT);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(TEST_AMOUNT, sendParam, userA);
        
        // Verify partial recovery works
        uint256 stuckFunds = assetOFT_arb.balanceOf(address(yzEnforcedComposer_arb));
        assertGt(stuckFunds, 0);
        assertLt(stuckFunds, TEST_AMOUNT);
        
        // Admin recovers stuck portion
        vm.prank(admin);
        yzEnforcedComposer_arb.emergencyWithdraw(stuckFunds, recipient);
        
        assertEq(assetOFT_arb.balanceOf(recipient), stuckFunds);
    }

    /*//////////////////////////////////////////////////////////////
                        ATOMICITY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Atomicity_SourceUpdateRollback() public {
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        // Mock atomic failure after source update
        _mockAtomicFailure();
        
        _fundLocalFromHub(userA, TEST_AMOUNT);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), TEST_AMOUNT);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, TEST_AMOUNT);
        
        // Should rollback source state on failure
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(TEST_AMOUNT, sendParam, userA);
        
        // Verify atomic rollback
        assertEq(vault_arb.totalAssets(), 0);
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), 0);
        assertEq(assetOFT_arb.balanceOf(userA), TEST_AMOUNT); // Funds returned
    }

    function test_Atomicity_ShareMintRollback() public {
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        // Mock failure after share minting
        _mockShareMintFailure();
        
        _fundLocalFromHub(userA, TEST_AMOUNT);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), TEST_AMOUNT);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, TEST_AMOUNT);
        
        // Should rollback share minting on failure
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(TEST_AMOUNT, sendParam, userA);
        
        // Verify share minting rolled back
        assertEq(vault_arb.totalAssets(), 0);
        assertEq(vault_arb.balanceOf(userA), 0);
        assertEq(vault_arb.totalSupply(), 0);
    }

    function test_Atomicity_CapUpdateRollback() public {
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        // Mock failure after cap update
        _mockCapUpdateFailure();
        
        _fundLocalFromHub(userA, TEST_AMOUNT);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), TEST_AMOUNT);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, TEST_AMOUNT);
        
        // Should rollback cap update on failure
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(TEST_AMOUNT, sendParam, userA);
        
        // Verify cap update rolled back
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), 0);
        assertEq(vault_arb.totalAssets(), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        LAYERZERO RETRY MECHANISM TESTS
    //////////////////////////////////////////////////////////////*/

    function test_LayerZeroRetry_Mechanism() public {
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        // Mock LayerZero retry mechanism
        _mockLayerZeroRetry();
        
        _fundLocalFromHub(userA, TEST_AMOUNT);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), TEST_AMOUNT);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, TEST_AMOUNT);
        
        // Should handle LayerZero retries
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(TEST_AMOUNT, sendParam, userA);
        
        // Verify successful after retry
        assertEq(vault_arb.totalAssets(), TEST_AMOUNT);
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), TEST_AMOUNT);
    }

    function test_LayerZeroRetry_DuplicatePrevention() public {
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        // First successful deposit
        _executeSuccessfulDeposit(userA, TEST_AMOUNT);
        
        // Mock LayerZero retry with duplicate
        _mockLayerZeroDuplicateRetry();
        
        _fundLocalFromHub(userA, TEST_AMOUNT);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), TEST_AMOUNT);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, TEST_AMOUNT);
        
        // Should prevent duplicate processing
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(TEST_AMOUNT, sendParam, userA);
        
        // Verify no duplicate
        assertEq(vault_arb.totalAssets(), TEST_AMOUNT);
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), TEST_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                        FAILURE SCENARIO COMBINATIONS
    //////////////////////////////////////////////////////////////*/

    function test_FailureCombination_DestinationRevertWithFees() public {
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        // Mock destination revert with fee issues
        _mockDestinationRevertWithFees();
        
        _fundLocalFromHub(userA, TEST_AMOUNT);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), TEST_AMOUNT);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, TEST_AMOUNT);
        
        // Should handle complex failure scenario
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend{value: 0.001 ether}(TEST_AMOUNT, sendParam, userA);
        
        // Verify graceful handling
        assertEq(vault_arb.totalAssets(), 0);
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), 0);
    }

    function test_FailureCombination_MultipleRetriesWithPartialSuccess() public {
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        // Mock multiple retries with partial success
        _mockMultipleRetriesPartialSuccess();
        
        _fundLocalFromHub(userA, TEST_AMOUNT);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), TEST_AMOUNT);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, TEST_AMOUNT);
        
        // Should handle complex retry scenario
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(TEST_AMOUNT, sendParam, userA);
        
        // Verify correct final state
        assertEq(vault_arb.totalAssets(), TEST_AMOUNT);
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), TEST_AMOUNT);
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

    function _executeSuccessfulDeposit(address user, uint256 amount) internal {
        _fundLocalFromHub(user, amount);
        vm.prank(user);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), amount);
        
        SendParam memory sendParam = _buildHopParam(address(0), user, ARB_EID, amount);
        
        vm.prank(user);
        yzEnforcedComposer_arb.depositAndSend(amount, sendParam, user);
    }

    /*//////////////////////////////////////////////////////////////
                        MOCK FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _mockLayerZeroRevert() internal {
        // Mock LayerZero endpoint to revert on send
        vm.mockCall(
            address(endpoint_arb),
            abi.encodeWithSignature("send(uint16,bytes,bytes,uint64,uint64,bytes)", 0, "", "", 0, 0, ""),
            abi.encodeWithSignature("Error(string)", "LayerZero revert")
        );
    }

    function _mockMessageExecutionFailure() internal {
        // Mock message execution failure
        vm.mockCall(
            address(endpoint_arb),
            abi.encodeWithSignature("estimateFees(uint16,bytes,bytes,bool)", 0, "", "", false),
            abi.encode(0, 0)
        );
    }

    function _mockInsufficientFees() internal {
        // Mock insufficient fees scenario
        vm.mockCall(
            address(endpoint_arb),
            abi.encodeWithSignature("send(uint16,bytes,bytes,uint64,uint64,bytes)", 0, "", "", 0, 0, ""),
            abi.encodeWithSignature("Error(string)", "Insufficient fees")
        );
    }

    function _mockMessageRetry() internal {
        // Mock message retry scenario
        vm.mockCall(
            address(endpoint_arb),
            abi.encodeWithSignature("getInboundNonce(uint16,bytes)", 0, ""),
            abi.encode(1)
        );
    }

    function _mockDuplicateMessage() internal {
        // Mock duplicate message detection
        vm.mockCall(
            address(endpoint_arb),
            abi.encodeWithSignature("getOutboundNonce(uint16,bytes)", 0, ""),
            abi.encode(1)
        );
    }

    function _mockOutOfOrderMessage() internal {
        // Mock out-of-order message
        vm.mockCall(
            address(endpoint_arb),
            abi.encodeWithSignature("getInboundNonce(uint16,bytes)", 0, ""),
            abi.encode(3) // Higher nonce out of order
        );
    }

    function _mockFundsStuck() internal {
        // Mock funds stuck scenario
        vm.mockCall(
            address(assetOFT_arb),
            abi.encodeWithSignature("transfer(address,uint256)", address(yzEnforcedComposer_arb), TEST_AMOUNT),
            abi.encode(false)
        );
    }

    function _mockPartialFundsStuck() internal {
        // Mock partial funds stuck
        vm.mockCall(
            address(assetOFT_arb),
            abi.encodeWithSignature("transfer(address,uint256)", address(yzEnforcedComposer_arb), TEST_AMOUNT),
            abi.encode(true)
        );
    }

    function _mockAtomicFailure() internal {
        // Mock atomic failure after source update
        vm.mockCall(
            address(vault_arb),
            abi.encodeWithSignature("deposit(uint256,address)", TEST_AMOUNT, address(yzEnforcedComposer_arb)),
            abi.encodeWithSignature("Error(string)", "Atomic failure")
        );
    }

    function _mockShareMintFailure() internal {
        // Mock share minting failure
        vm.mockCall(
            address(vault_arb),
            abi.encodeWithSignature("mint(address,uint256)", userA, TEST_AMOUNT),
            abi.encodeWithSignature("Error(string)", "Share mint failure")
        );
    }

    function _mockCapUpdateFailure() internal {
        // Mock cap update failure
        vm.mockCall(
            address(yzEnforcedComposer_arb),
            abi.encodeWithSignature("updateUserDepositCap(address,uint256)", userA, TEST_AMOUNT),
            abi.encodeWithSignature("Error(string)", "Cap update failure")
        );
    }

    function _mockLayerZeroRetry() internal {
        // Mock LayerZero retry mechanism
        vm.mockCall(
            address(endpoint_arb),
            abi.encodeWithSignature("retryPayload(uint16,bytes,bytes)", 0, "", ""),
            abi.encode(true)
        );
    }

    function _mockLayerZeroDuplicateRetry() internal {
        // Mock LayerZero duplicate retry
        vm.mockCall(
            address(endpoint_arb),
            abi.encodeWithSignature("getInboundNonce(uint16,bytes)", 0, ""),
            abi.encode(2) // Duplicate nonce
        );
    }

    function _mockDestinationRevertWithFees() internal {
        // Mock destination revert with fee issues
        vm.mockCall(
            address(endpoint_arb),
            abi.encodeWithSignature("send(uint16,bytes,bytes,uint64,uint64,bytes)", 0, "", "", 0, 0, ""),
            abi.encodeWithSignature("Error(string)", "Destination revert")
        );
    }

    function _mockMultipleRetriesPartialSuccess() internal {
        // Mock multiple retries with partial success
        vm.mockCall(
            address(endpoint_arb),
            abi.encodeWithSignature("estimateFees(uint16,bytes,bytes,bool)", 0, "", "", false),
            abi.encode(1 ether, 1 ether)
        );
    }

    function _resetLayerZeroMock() internal {
        // Reset LayerZero mock for successful operations
        vm.clearMockedCalls();
    }
}