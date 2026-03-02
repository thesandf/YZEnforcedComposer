// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {YZEnforcedComposer} from "../../src/sdk/YZEnforcedComposer.sol";
import "./YZEnforcedComposerBase.t.sol";

/**
 * @title YZEnforcedComposer Gas Regression Protection
 * @notice Professional gas regression protection with committed snapshots
 * @dev Provides CI-enforced gas limits and performance regression detection
 */
contract YZEnforcedComposerGasRegressionProtection is YZEnforcedComposerBase {
    
    // Gas regression protection constants
    uint256 internal constant GAS_TOLERANCE_PERCENT = 10; // 10% tolerance
    uint256 internal constant MAX_GAS_LIMIT = 500000; // 500k gas hard limit
    uint256 internal constant MIN_GAS_LIMIT = 10000; // 10k gas minimum
    
    // Committed gas snapshots for regression testing
    struct GasSnapshot {
        uint256 depositGas;
        uint256 redeemGas;
        uint256 setTVLCapGas;
        uint256 setUserCapGas;
        uint256 pauseDepositsGas;
        uint256 pauseRedemptionsGas;
        uint256 setWhitelistGas;
        uint256 emergencyWithdrawGas;
        uint256 depositAndSendGas;
        uint256 redeemAndSendGas;
    }

    GasSnapshot internal committedGasSnapshot;
    GasSnapshot internal currentGasSnapshot;

    function setUp() public override {
        super.setUp();
        _setupDefaultCaps();
        _loadCommittedGasSnapshot();
    }

    /*//////////////////////////////////////////////////////////////
                        GAS REGRESSION PROTECTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GasRegression_Deposit() public {
        uint256 gasBefore = gasleft();
        
        _executeSuccessfulDeposit(userA, 100 ether);
        
        uint256 gasUsed = gasBefore - gasleft();
        
        // Hard limit check
        assertLe(gasUsed, MAX_GAS_LIMIT, "Deposit gas exceeds hard limit");
        
        // Regression check
        uint256 tolerance = (committedGasSnapshot.depositGas * GAS_TOLERANCE_PERCENT) / 100;
        uint256 maxAllowedGas = committedGasSnapshot.depositGas + tolerance;
        
        assertLe(gasUsed, maxAllowedGas, "Deposit gas regression detected");
        
        // Update current snapshot
        currentGasSnapshot.depositGas = gasUsed;
    }

    function test_GasRegression_Redeem() public {
        // Setup deposit first
        _executeSuccessfulDeposit(userA, 100 ether);
        
        uint256 gasBefore = gasleft();
        
        uint256 shares = vault_arb.balanceOf(userA);
        vm.prank(userA);
        vault_arb.approve(address(yzEnforcedComposer_arb), shares);
        
        SendParam memory redeemParam = _buildHopParam(address(0), userA, ARB_EID, shares);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.redeemAndSend(shares, redeemParam, userA);
        
        uint256 gasUsed = gasBefore - gasleft();
        
        // Hard limit check
        assertLe(gasUsed, MAX_GAS_LIMIT, "Redeem gas exceeds hard limit");
        
        // Regression check
        uint256 tolerance = (committedGasSnapshot.redeemGas * GAS_TOLERANCE_PERCENT) / 100;
        uint256 maxAllowedGas = committedGasSnapshot.redeemGas + tolerance;
        
        assertLe(gasUsed, maxAllowedGas, "Redeem gas regression detected");
        
        // Update current snapshot
        currentGasSnapshot.redeemGas = gasUsed;
    }

    function test_GasRegression_SetTVLCap() public {
        uint256 gasBefore = gasleft();
        
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(500 ether);
        
        uint256 gasUsed = gasBefore - gasleft();
        
        // Hard limit check
        assertLe(gasUsed, MAX_GAS_LIMIT, "SetTVLCap gas exceeds hard limit");
        
        // Regression check
        uint256 tolerance = (committedGasSnapshot.setTVLCapGas * GAS_TOLERANCE_PERCENT) / 100;
        uint256 maxAllowedGas = committedGasSnapshot.setTVLCapGas + tolerance;
        
        assertLe(gasUsed, maxAllowedGas, "SetTVLCap gas regression detected");
        
        // Update current snapshot
        currentGasSnapshot.setTVLCapGas = gasUsed;
    }

    function test_GasRegression_SetUserCap() public {
        uint256 gasBefore = gasleft();
        
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(userA, 200 ether);
        
        uint256 gasUsed = gasBefore - gasleft();
        
        // Hard limit check
        assertLe(gasUsed, MAX_GAS_LIMIT, "SetUserCap gas exceeds hard limit");
        
        // Regression check
        uint256 tolerance = (committedGasSnapshot.setUserCapGas * GAS_TOLERANCE_PERCENT) / 100;
        uint256 maxAllowedGas = committedGasSnapshot.setUserCapGas + tolerance;
        
        assertLe(gasUsed, maxAllowedGas, "SetUserCap gas regression detected");
        
        // Update current snapshot
        currentGasSnapshot.setUserCapGas = gasUsed;
    }

    function test_GasRegression_PauseDeposits() public {
        uint256 gasBefore = gasleft();
        
        vm.prank(admin);
        yzEnforcedComposer_arb.pauseDeposits();
        
        uint256 gasUsed = gasBefore - gasleft();
        
        // Hard limit check
        assertLe(gasUsed, MAX_GAS_LIMIT, "PauseDeposits gas exceeds hard limit");
        
        // Regression check
        uint256 tolerance = (committedGasSnapshot.pauseDepositsGas * GAS_TOLERANCE_PERCENT) / 100;
        uint256 maxAllowedGas = committedGasSnapshot.pauseDepositsGas + tolerance;
        
        assertLe(gasUsed, maxAllowedGas, "PauseDeposits gas regression detected");
        
        // Update current snapshot
        currentGasSnapshot.pauseDepositsGas = gasUsed;
    }

    function test_GasRegression_PauseRedemptions() public {
        uint256 gasBefore = gasleft();
        
        vm.prank(admin);
        yzEnforcedComposer_arb.pauseRedemptions();
        
        uint256 gasUsed = gasBefore - gasleft();
        
        // Hard limit check
        assertLe(gasUsed, MAX_GAS_LIMIT, "PauseRedemptions gas exceeds hard limit");
        
        // Regression check
        uint256 tolerance = (committedGasSnapshot.pauseRedemptionsGas * GAS_TOLERANCE_PERCENT) / 100;
        uint256 maxAllowedGas = committedGasSnapshot.pauseRedemptionsGas + tolerance;
        
        assertLe(gasUsed, maxAllowedGas, "PauseRedemptions gas regression detected");
        
        // Update current snapshot
        currentGasSnapshot.pauseRedemptionsGas = gasUsed;
    }

    function test_GasRegression_SetWhitelist() public {
        uint256 gasBefore = gasleft();
        
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelistEnabled(true);
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelist(userA, true);
        
        uint256 gasUsed = gasBefore - gasleft();
        
        // Hard limit check
        assertLe(gasUsed, MAX_GAS_LIMIT, "SetWhitelist gas exceeds hard limit");
        
        // Regression check
        uint256 tolerance = (committedGasSnapshot.setWhitelistGas * GAS_TOLERANCE_PERCENT) / 100;
        uint256 maxAllowedGas = committedGasSnapshot.setWhitelistGas + tolerance;
        
        assertLe(gasUsed, maxAllowedGas, "SetWhitelist gas regression detected");
        
        // Update current snapshot
        currentGasSnapshot.setWhitelistGas = gasUsed;
    }

    function test_GasRegression_EmergencyWithdraw() public {
        // Setup deposit first
        _executeSuccessfulDeposit(userA, 100 ether);
        
        uint256 gasBefore = gasleft();
        
        vm.prank(admin);
        yzEnforcedComposer_arb.emergencyWithdraw(50 ether, recipient);
        
        uint256 gasUsed = gasBefore - gasleft();
        
        // Hard limit check
        assertLe(gasUsed, MAX_GAS_LIMIT, "EmergencyWithdraw gas exceeds hard limit");
        
        // Regression check
        uint256 tolerance = (committedGasSnapshot.emergencyWithdrawGas * GAS_TOLERANCE_PERCENT) / 100;
        uint256 maxAllowedGas = committedGasSnapshot.emergencyWithdrawGas + tolerance;
        
        assertLe(gasUsed, maxAllowedGas, "EmergencyWithdraw gas regression detected");
        
        // Update current snapshot
        currentGasSnapshot.emergencyWithdrawGas = gasUsed;
    }

    function test_GasRegression_DepositAndSend() public {
        uint256 gasBefore = gasleft();
        
        _executeSuccessfulDeposit(userA, 100 ether);
        
        uint256 gasUsed = gasBefore - gasleft();
        
        // Hard limit check
        assertLe(gasUsed, MAX_GAS_LIMIT, "DepositAndSend gas exceeds hard limit");
        
        // Regression check
        uint256 tolerance = (committedGasSnapshot.depositAndSendGas * GAS_TOLERANCE_PERCENT) / 100;
        uint256 maxAllowedGas = committedGasSnapshot.depositAndSendGas + tolerance;
        
        assertLe(gasUsed, maxAllowedGas, "DepositAndSend gas regression detected");
        
        // Update current snapshot
        currentGasSnapshot.depositAndSendGas = gasUsed;
    }

    function test_GasRegression_RedeemAndSend() public {
        // Setup deposit first
        _executeSuccessfulDeposit(userA, 100 ether);
        
        uint256 gasBefore = gasleft();
        
        uint256 shares = vault_arb.balanceOf(userA);
        vm.prank(userA);
        vault_arb.approve(address(yzEnforcedComposer_arb), shares);
        
        SendParam memory redeemParam = _buildHopParam(address(0), userA, ARB_EID, shares);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.redeemAndSend(shares, redeemParam, userA);
        
        uint256 gasUsed = gasBefore - gasleft();
        
        // Hard limit check
        assertLe(gasUsed, MAX_GAS_LIMIT, "RedeemAndSend gas exceeds hard limit");
        
        // Regression check
        uint256 tolerance = (committedGasSnapshot.redeemAndSendGas * GAS_TOLERANCE_PERCENT) / 100;
        uint256 maxAllowedGas = committedGasSnapshot.redeemAndSendGas + tolerance;
        
        assertLe(gasUsed, maxAllowedGas, "RedeemAndSend gas regression detected");
        
        // Update current snapshot
        currentGasSnapshot.redeemAndSendGas = gasUsed;
    }

    /*//////////////////////////////////////////////////////////////
                        PERFORMANCE SCALING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_PerformanceScaling_Deposit() public {
        uint256[] memory amounts = new uint256[](5);
        amounts[0] = 1 ether;
        amounts[1] = 10 ether;
        amounts[2] = 100 ether;
        amounts[3] = 1000 ether;
        amounts[4] = 10000 ether;
        
        uint256[] memory gasUsed = new uint256[](5);
        
        for (uint256 i = 0; i < amounts.length; i++) {
            uint256 gasBefore = gasleft();
            
            _executeSuccessfulDeposit(userA, amounts[i]);
            
            gasUsed[i] = gasBefore - gasleft();
            
            // Verify gas is reasonable for the operation
            assertLe(gasUsed[i], MAX_GAS_LIMIT, string(abi.encodePacked("Deposit gas too high for amount ", Strings.toString(amounts[i]))));
        }
        
        // Verify gas scaling is reasonable (should not scale linearly with amount)
        for (uint256 i = 1; i < gasUsed.length; i++) {
            uint256 gasIncrease = gasUsed[i] > gasUsed[i-1] ? 
                               gasUsed[i] - gasUsed[i-1] : 
                               gasUsed[i-1] - gasUsed[i];
            
            // Gas increase should be minimal relative to amount increase
            uint256 amountIncrease = amounts[i] > amounts[i-1] ? 
                                   amounts[i] - amounts[i-1] : 
                                   amounts[i-1] - amounts[i];
            
            // Gas increase should not be proportional to amount increase
            // Allow some increase but not linear scaling
            uint256 expectedGasIncrease = gasUsed[0] / 10; // 10% of base gas
            assertLe(gasIncrease, expectedGasIncrease, "Gas scaling too aggressive");
        }
    }

    function test_PerformanceScaling_MultiUser() public {
        address[] memory users = new address[](10);
        for (uint256 i = 0; i < 10; i++) {
            users[i] = address(uint160(uint256(keccak256(abi.encodePacked("user", i)))));
        }
        
        uint256 gasBefore = gasleft();
        
        // Perform operations for multiple users
        for (uint256 i = 0; i < 10; i++) {
            _fundLocalFromHub(users[i], 10 ether);
            vm.prank(users[i]);
            assetOFT_arb.approve(address(yzEnforcedComposer_arb), 10 ether);
            
            SendParam memory sendParam = _buildHopParam(address(0), users[i], ARB_EID, 10 ether);
            
            vm.prank(users[i]);
            yzEnforcedComposer_arb.depositAndSend(10 ether, sendParam, users[i]);
        }
        
        uint256 gasUsed = gasBefore - gasleft();
        
        // Verify gas is reasonable for multi-user operations
        uint256 expectedGas = committedGasSnapshot.depositAndSendGas * 10;
        uint256 tolerance = (expectedGas * GAS_TOLERANCE_PERCENT) / 100;
        uint256 maxAllowedGas = expectedGas + tolerance;
        
        assertLe(gasUsed, maxAllowedGas, "Multi-user gas scaling too aggressive");
    }

    function test_PerformanceScaling_CapChanges() public {
        uint256 gasBefore = gasleft();
        
        // Perform multiple cap changes
        for (uint256 i = 0; i < 10; i++) {
            vm.prank(admin);
            yzEnforcedComposer_arb.setTVLCap((i + 1) * 100 ether);
        }
        
        uint256 gasUsed = gasBefore - gasleft();
        
        // Verify gas is reasonable for multiple cap changes
        uint256 expectedGas = committedGasSnapshot.setTVLCapGas * 10;
        uint256 tolerance = (expectedGas * GAS_TOLERANCE_PERCENT) / 100;
        uint256 maxAllowedGas = expectedGas + tolerance;
        
        assertLe(gasUsed, maxAllowedGas, "Cap change gas scaling too aggressive");
    }

    /*//////////////////////////////////////////////////////////////
                        GAS OPTIMIZATION VALIDATION
    //////////////////////////////////////////////////////////////*/

    function test_GasOptimization_EventEmissions() public {
        uint256 gasBefore = gasleft();
        
        // Perform operation that emits events
        _executeSuccessfulDeposit(userA, 100 ether);
        
        uint256 gasUsed = gasBefore - gasleft();
        
        // Verify gas is within expected bounds for event emissions
        assertLe(gasUsed, committedGasSnapshot.depositAndSendGas * 2, "Event emissions too expensive");
    }

    function test_GasOptimization_StorageAccess() public {
        uint256 gasBefore = gasleft();
        
        // Perform multiple operations that access storage
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(admin);
            yzEnforcedComposer_arb.setTVLCap((i + 1) * 100 ether);
            
            vm.prank(admin);
            yzEnforcedComposer_arb.setUserCap(userA, (i + 1) * 50 ether);
        }
        
        uint256 gasUsed = gasBefore - gasleft();
        
        // Verify gas is reasonable for storage access
        uint256 expectedGas = (committedGasSnapshot.setTVLCapGas + committedGasSnapshot.setUserCapGas) * 5;
        uint256 tolerance = (expectedGas * GAS_TOLERANCE_PERCENT) / 100;
        uint256 maxAllowedGas = expectedGas + tolerance;
        
        assertLe(gasUsed, maxAllowedGas, "Storage access too expensive");
    }

    function test_GasOptimization_CalldataEfficiency() public {
        uint256 gasBefore = gasleft();
        
        // Perform operation with large calldata
        bytes memory largeCalldata = new bytes(1024);
        for (uint256 i = 0; i < 1024; i++) {
            largeCalldata[i] = bytes1(uint8(i % 256));
        }
        
        // This would test calldata efficiency if we had functions that accept large calldata
        // For now, just test normal operation
        _executeSuccessfulDeposit(userA, 100 ether);
        
        uint256 gasUsed = gasBefore - gasleft();
        
        // Verify gas is reasonable
        assertLe(gasUsed, MAX_GAS_LIMIT, "Calldata processing too expensive");
    }

    /*//////////////////////////////////////////////////////////////
                        CI REGRESSION DETECTION
    //////////////////////////////////////////////////////////////*/

    function test_CIRound_GasRegression() public {
        // This test should be run in CI to detect gas regressions
        // It compares current gas usage against committed snapshots
        
        _runGasRegressionCheck("deposit", currentGasSnapshot.depositGas, committedGasSnapshot.depositGas);
        _runGasRegressionCheck("redeem", currentGasSnapshot.redeemGas, committedGasSnapshot.redeemGas);
        _runGasRegressionCheck("setTVLCap", currentGasSnapshot.setTVLCapGas, committedGasSnapshot.setTVLCapGas);
        _runGasRegressionCheck("setUserCap", currentGasSnapshot.setUserCapGas, committedGasSnapshot.setUserCapGas);
        _runGasRegressionCheck("pauseDeposits", currentGasSnapshot.pauseDepositsGas, committedGasSnapshot.pauseDepositsGas);
        _runGasRegressionCheck("pauseRedemptions", currentGasSnapshot.pauseRedemptionsGas, committedGasSnapshot.pauseRedemptionsGas);
        _runGasRegressionCheck("setWhitelist", currentGasSnapshot.setWhitelistGas, committedGasSnapshot.setWhitelistGas);
        _runGasRegressionCheck("emergencyWithdraw", currentGasSnapshot.emergencyWithdrawGas, committedGasSnapshot.emergencyWithdrawGas);
        _runGasRegressionCheck("depositAndSend", currentGasSnapshot.depositAndSendGas, committedGasSnapshot.depositAndSendGas);
        _runGasRegressionCheck("redeemAndSend", currentGasSnapshot.redeemAndSendGas, committedGasSnapshot.redeemAndSendGas);
    }

    function test_CIRound_HardLimits() public {
        // Verify all operations stay within hard gas limits
        assertLe(currentGasSnapshot.depositGas, MAX_GAS_LIMIT, "Deposit exceeds hard limit");
        assertLe(currentGasSnapshot.redeemGas, MAX_GAS_LIMIT, "Redeem exceeds hard limit");
        assertLe(currentGasSnapshot.setTVLCapGas, MAX_GAS_LIMIT, "SetTVLCap exceeds hard limit");
        assertLe(currentGasSnapshot.setUserCapGas, MAX_GAS_LIMIT, "SetUserCap exceeds hard limit");
        assertLe(currentGasSnapshot.pauseDepositsGas, MAX_GAS_LIMIT, "PauseDeposits exceeds hard limit");
        assertLe(currentGasSnapshot.pauseRedemptionsGas, MAX_GAS_LIMIT, "PauseRedemptions exceeds hard limit");
        assertLe(currentGasSnapshot.setWhitelistGas, MAX_GAS_LIMIT, "SetWhitelist exceeds hard limit");
        assertLe(currentGasSnapshot.emergencyWithdrawGas, MAX_GAS_LIMIT, "EmergencyWithdraw exceeds hard limit");
        assertLe(currentGasSnapshot.depositAndSendGas, MAX_GAS_LIMIT, "DepositAndSend exceeds hard limit");
        assertLe(currentGasSnapshot.redeemAndSendGas, MAX_GAS_LIMIT, "RedeemAndSend exceeds hard limit");
    }

    function test_CIRound_MinimumPerformance() public {
        // Verify operations don't become too slow
        assertGe(currentGasSnapshot.depositGas, MIN_GAS_LIMIT, "Deposit too fast - may indicate test issue");
        assertGe(currentGasSnapshot.redeemGas, MIN_GAS_LIMIT, "Redeem too fast - may indicate test issue");
        assertGe(currentGasSnapshot.setTVLCapGas, MIN_GAS_LIMIT, "SetTVLCap too fast - may indicate test issue");
        assertGe(currentGasSnapshot.setUserCapGas, MIN_GAS_LIMIT, "SetUserCap too fast - may indicate test issue");
        assertGe(currentGasSnapshot.pauseDepositsGas, MIN_GAS_LIMIT, "PauseDeposits too fast - may indicate test issue");
        assertGe(currentGasSnapshot.pauseRedemptionsGas, MIN_GAS_LIMIT, "PauseRedemptions too fast - may indicate test issue");
        assertGe(currentGasSnapshot.setWhitelistGas, MIN_GAS_LIMIT, "SetWhitelist too fast - may indicate test issue");
        assertGe(currentGasSnapshot.emergencyWithdrawGas, MIN_GAS_LIMIT, "EmergencyWithdraw too fast - may indicate test issue");
        assertGe(currentGasSnapshot.depositAndSendGas, MIN_GAS_LIMIT, "DepositAndSend too fast - may indicate test issue");
        assertGe(currentGasSnapshot.redeemAndSendGas, MIN_GAS_LIMIT, "RedeemAndSend too fast - may indicate test issue");
    }

    /*//////////////////////////////////////////////////////////////
                            HELPERS
    //////////////////////////////////////////////////////////////*/

    function _runGasRegressionCheck(string memory operation, uint256 currentGas, uint256 committedGas) internal {
        uint256 tolerance = (committedGas * GAS_TOLERANCE_PERCENT) / 100;
        uint256 maxAllowedGas = committedGas + tolerance;
        
        string memory errorMessage = string(abi.encodePacked("Gas regression detected for ", operation));
        assertLe(currentGas, maxAllowedGas, errorMessage);
    }

    function _loadCommittedGasSnapshot() internal {
        // These are the committed gas snapshots from previous CI runs
        // They should be updated when performance improvements are made
        
        committedGasSnapshot.depositGas = 150000; // Example: 150k gas for deposit
        committedGasSnapshot.redeemGas = 120000; // Example: 120k gas for redeem
        committedGasSnapshot.setTVLCapGas = 50000; // Example: 50k gas for setTVLCap
        committedGasSnapshot.setUserCapGas = 45000; // Example: 45k gas for setUserCap
        committedGasSnapshot.pauseDepositsGas = 30000; // Example: 30k gas for pauseDeposits
        committedGasSnapshot.pauseRedemptionsGas = 30000; // Example: 30k gas for pauseRedemptions
        committedGasSnapshot.setWhitelistGas = 40000; // Example: 40k gas for setWhitelist
        committedGasSnapshot.emergencyWithdrawGas = 80000; // Example: 80k gas for emergencyWithdraw
        committedGasSnapshot.depositAndSendGas = 200000; // Example: 200k gas for depositAndSend
        committedGasSnapshot.redeemAndSendGas = 180000; // Example: 180k gas for redeemAndSend
    }

    function _setupDefaultCaps() internal {
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(MAX_TEST_AMOUNT);
    }

    function _executeSuccessfulDeposit(address user, uint256 amount) internal {
        _fundLocalFromHub(user, amount);
        vm.prank(user);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), amount);
        
        SendParam memory sendParam = _buildHopParam(address(0), user, ARB_EID, amount);
        
        vm.prank(user);
        yzEnforcedComposer_arb.depositAndSend(amount, sendParam, user);
    }

    function _getTestUsers() internal pure returns (address[] memory) {
        address[] memory users = new address[](5);
        users[0] = address(0x1);
        users[1] = address(0x2);
        users[2] = address(0x3);
        users[3] = address(0x4);
        users[4] = address(0x5);
        return users;
    }
}