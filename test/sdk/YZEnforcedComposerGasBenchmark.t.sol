// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {YZEnforcedComposer} from "../../src/sdk/YZEnforcedComposer.sol";
import "./YZEnforcedComposerBase.t.sol";

/**
 * @title YZEnforcedComposer Gas Benchmark Tests
 * @notice Professional gas benchmarking and performance tests
 * @dev Tests gas usage, performance regression, and optimization validation
 */
contract YZEnforcedComposerGasBenchmarkTest is YZEnforcedComposerBase {
    
    // Test constants
    uint256 internal constant BENCHMARK_AMOUNT = 100 ether;
    uint256 internal constant GAS_LIMIT_THRESHOLD = 500000; // 500k gas threshold
    uint256 internal constant PERFORMANCE_TOLERANCE = 10; // 10% tolerance

    function setUp() public override {
        super.setUp();
        _setupDefaultCaps();
    }

    /*//////////////////////////////////////////////////////////////
                        GAS BENCHMARK TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GasBenchmark_DepositOperation() public {
        _setupUserCap(userA, 1000 ether);
        _setupTVLCap(2000 ether);
        
        _fundLocalFromHub(userA, BENCHMARK_AMOUNT);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), BENCHMARK_AMOUNT);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, BENCHMARK_AMOUNT);
        
        uint256 gasBefore = gasleft();
        
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(BENCHMARK_AMOUNT, sendParam, userA);
        
        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;
        
        // Verify gas usage is within reasonable bounds
        assertLt(gasUsed, GAS_LIMIT_THRESHOLD, "Deposit gas usage too high");
        
        // Log gas usage for monitoring
        emit log_named_uint("Deposit Gas Used", gasUsed);
    }

    function test_GasBenchmark_RedeemOperation() public {
        // First deposit for redeem test
        _setupUserCap(userA, 1000 ether);
        _setupTVLCap(2000 ether);
        _executeSuccessfulDeposit(userA, BENCHMARK_AMOUNT);
        
        uint256 redeemAmount = BENCHMARK_AMOUNT / 2;
        vm.prank(userA);
        vault_arb.approve(address(yzEnforcedComposer_arb), redeemAmount);
        
        SendParam memory redeemParam = _buildHopParam(address(0), userA, ARB_EID, redeemAmount);
        
        uint256 gasBefore = gasleft();
        
        vm.prank(userA);
        yzEnforcedComposer_arb.redeemAndSend(redeemAmount, redeemParam, userA);
        
        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;
        
        // Verify gas usage is within reasonable bounds
        assertLt(gasUsed, GAS_LIMIT_THRESHOLD, "Redeem gas usage too high");
        
        // Log gas usage for monitoring
        emit log_named_uint("Redeem Gas Used", gasUsed);
    }

    function test_GasBenchmark_CapManagementOperations() public {
        uint256 gasBefore;
        uint256 gasAfter;
        uint256 gasUsed;
        
        // Test setTVLCap gas usage
        gasBefore = gasleft();
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(1000 ether);
        gasAfter = gasleft();
        gasUsed = gasBefore - gasAfter;
        
        assertLt(gasUsed, 50000, "setTVLCap gas usage too high");
        emit log_named_uint("setTVLCap Gas Used", gasUsed);
        
        // Test setUserCap gas usage
        gasBefore = gasleft();
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(userA, 500 ether);
        gasAfter = gasleft();
        gasUsed = gasBefore - gasAfter;
        
        assertLt(gasUsed, 50000, "setUserCap gas usage too high");
        emit log_named_uint("setUserCap Gas Used", gasUsed);
        
        // Test batchSetUserCaps gas usage
        address[] memory users = new address[](3);
        users[0] = userA;
        users[1] = userB;
        users[2] = userC;
        
        uint256[] memory caps = new uint256[](3);
        caps[0] = 100 ether;
        caps[1] = 200 ether;
        caps[2] = 300 ether;
        
        gasBefore = gasleft();
        vm.prank(admin);
        yzEnforcedComposer_arb.batchSetUserCaps(users, caps);
        gasAfter = gasleft();
        gasUsed = gasBefore - gasAfter;
        
        assertLt(gasUsed, 100000, "batchSetUserCaps gas usage too high");
        emit log_named_uint("batchSetUserCaps Gas Used", gasUsed);
    }

    function test_GasBenchmark_PauseControlOperations() public {
        uint256 gasBefore;
        uint256 gasAfter;
        uint256 gasUsed;
        
        // Test pauseDeposits gas usage
        gasBefore = gasleft();
        vm.prank(admin);
        yzEnforcedComposer_arb.pauseDeposits();
        gasAfter = gasleft();
        gasUsed = gasBefore - gasAfter;
        
        assertLt(gasUsed, 30000, "pauseDeposits gas usage too high");
        emit log_named_uint("pauseDeposits Gas Used", gasUsed);
        
        // Test unpauseDeposits gas usage
        gasBefore = gasleft();
        vm.prank(admin);
        yzEnforcedComposer_arb.unpauseDeposits();
        gasAfter = gasleft();
        gasUsed = gasBefore - gasAfter;
        
        assertLt(gasUsed, 30000, "unpauseDeposits gas usage too high");
        emit log_named_uint("unpauseDeposits Gas Used", gasUsed);
        
        // Test pauseRedemptions gas usage
        gasBefore = gasleft();
        vm.prank(admin);
        yzEnforcedComposer_arb.pauseRedemptions();
        gasAfter = gasleft();
        gasUsed = gasBefore - gasAfter;
        
        assertLt(gasUsed, 30000, "pauseRedemptions gas usage too high");
        emit log_named_uint("pauseRedemptions Gas Used", gasUsed);
        
        // Test unpauseRedemptions gas usage
        gasBefore = gasleft();
        vm.prank(admin);
        yzEnforcedComposer_arb.unpauseRedemptions();
        gasAfter = gasleft();
        gasUsed = gasBefore - gasAfter;
        
        assertLt(gasUsed, 30000, "unpauseRedemptions gas usage too high");
        emit log_named_uint("unpauseRedemptions Gas Used", gasUsed);
    }

    function test_GasBenchmark_WhitelistOperations() public {
        uint256 gasBefore;
        uint256 gasAfter;
        uint256 gasUsed;
        
        // Test setWhitelistEnabled gas usage
        gasBefore = gasleft();
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelistEnabled(true);
        gasAfter = gasleft();
        gasUsed = gasBefore - gasAfter;
        
        assertLt(gasUsed, 30000, "setWhitelistEnabled gas usage too high");
        emit log_named_uint("setWhitelistEnabled Gas Used", gasUsed);
        
        // Test setWhitelist gas usage
        gasBefore = gasleft();
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelist(userA, true);
        gasAfter = gasleft();
        gasUsed = gasBefore - gasAfter;
        
        assertLt(gasUsed, 30000, "setWhitelist gas usage too high");
        emit log_named_uint("setWhitelist Gas Used", gasUsed);
        
        // Test batchSetWhitelist gas usage
        address[] memory users = new address[](3);
        users[0] = userA;
        users[1] = userB;
        users[2] = userC;
        
        bool[] memory statuses = new bool[](3);
        statuses[0] = true;
        statuses[1] = false;
        statuses[2] = true;
        
        gasBefore = gasleft();
        vm.prank(admin);
        yzEnforcedComposer_arb.batchSetWhitelist(users, statuses);
        gasAfter = gasleft();
        gasUsed = gasBefore - gasAfter;
        
        assertLt(gasUsed, 60000, "batchSetWhitelist gas usage too high");
        emit log_named_uint("batchSetWhitelist Gas Used", gasUsed);
    }

    function test_GasBenchmark_ViewOperations() public {
        _setupUserCap(userA, 1000 ether);
        _setupTVLCap(2000 ether);
        _executeSuccessfulDeposit(userA, BENCHMARK_AMOUNT);
        
        uint256 gasBefore;
        uint256 gasAfter;
        uint256 gasUsed;
        
        // Test getTotalValueLocked gas usage
        gasBefore = gasleft();
        uint256 tvl = yzEnforcedComposer_arb.getTotalValueLocked();
        gasAfter = gasleft();
        gasUsed = gasBefore - gasAfter;
        
        assertLt(gasUsed, 20000, "getTotalValueLocked gas usage too high");
        emit log_named_uint("getTotalValueLocked Gas Used", gasUsed);
        
        // Test getUserShares gas usage
        gasBefore = gasleft();
        uint256 shares = yzEnforcedComposer_arb.getUserShares(userA);
        gasAfter = gasleft();
        gasUsed = gasBefore - gasAfter;
        
        assertLt(gasUsed, 20000, "getUserShares gas usage too high");
        emit log_named_uint("getUserShares Gas Used", gasUsed);
        
        // Test getUserAssets gas usage
        gasBefore = gasleft();
        uint256 assets = yzEnforcedComposer_arb.getUserAssets(userA);
        gasAfter = gasleft();
        gasUsed = gasBefore - gasAfter;
        
        assertLt(gasUsed, 20000, "getUserAssets gas usage too high");
        emit log_named_uint("getUserAssets Gas Used", gasUsed);
        
        // Test getUserDepositInfo gas usage
        gasBefore = gasleft();
        (uint256 deposit, uint256 cap, uint256 remaining) = yzEnforcedComposer_arb.getUserDepositInfo(userA);
        gasAfter = gasleft();
        gasUsed = gasBefore - gasAfter;
        
        assertLt(gasUsed, 20000, "getUserDepositInfo gas usage too high");
        emit log_named_uint("getUserDepositInfo Gas Used", gasUsed);
        
        // Test canDeposit gas usage
        gasBefore = gasleft();
        (bool canDeposit, ) = yzEnforcedComposer_arb.canDeposit(userA, BENCHMARK_AMOUNT);
        gasAfter = gasleft();
        gasUsed = gasBefore - gasAfter;
        
        assertLt(gasUsed, 20000, "canDeposit gas usage too high");
        emit log_named_uint("canDeposit Gas Used", gasUsed);
    }

    function test_GasBenchmark_EmergencyOperations() public {
        uint256 gasBefore;
        uint256 gasAfter;
        uint256 gasUsed;
        
        // Test emergencyWithdraw gas usage
        _fundLocalFromHub(address(yzEnforcedComposer_arb), BENCHMARK_AMOUNT);
        
        gasBefore = gasleft();
        vm.prank(admin);
        yzEnforcedComposer_arb.emergencyWithdraw(BENCHMARK_AMOUNT, recipient);
        gasAfter = gasleft();
        gasUsed = gasBefore - gasAfter;
        
        assertLt(gasUsed, 50000, "emergencyWithdraw gas usage too high");
        emit log_named_uint("emergencyWithdraw Gas Used", gasUsed);
        
        // Test emergencyWithdrawShares gas usage
        _executeSuccessfulDeposit(userA, BENCHMARK_AMOUNT);
        vm.prank(address(yzEnforcedComposer_arb));
        vault_arb.approve(address(yzEnforcedComposer_arb), BENCHMARK_AMOUNT);
        
        gasBefore = gasleft();
        vm.prank(admin);
        yzEnforcedComposer_arb.emergencyWithdrawShares(BENCHMARK_AMOUNT, recipient);
        gasAfter = gasleft();
        gasUsed = gasBefore - gasAfter;
        
        assertLt(gasUsed, 50000, "emergencyWithdrawShares gas usage too high");
        emit log_named_uint("emergencyWithdrawShares Gas Used", gasUsed);
        
        // Test emergencyWithdrawNative gas usage
        vm.deal(address(yzEnforcedComposer_arb), BENCHMARK_AMOUNT);
        
        gasBefore = gasleft();
        vm.prank(admin);
        yzEnforcedComposer_arb.emergencyWithdrawNative(BENCHMARK_AMOUNT, payable(recipient));
        gasAfter = gasleft();
        gasUsed = gasBefore - gasAfter;
        
        assertLt(gasUsed, 50000, "emergencyWithdrawNative gas usage too high");
        emit log_named_uint("emergencyWithdrawNative Gas Used", gasUsed);
    }

    /*//////////////////////////////////////////////////////////////
                        PERFORMANCE REGRESSION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_PerformanceRegression_DepositScaling() public {
        _setupUserCap(userA, 10000 ether);
        _setupTVLCap(20000 ether);
        
        uint256[] memory depositAmounts = new uint256[](5);
        depositAmounts[0] = 1 ether;
        depositAmounts[1] = 10 ether;
        depositAmounts[2] = 100 ether;
        depositAmounts[3] = 1000 ether;
        depositAmounts[4] = 10000 ether;
        
        uint256[] memory gasUsages = new uint256[](5);
        
        for (uint256 i = 0; i < depositAmounts.length; i++) {
            uint256 amount = depositAmounts[i];
            
            _fundLocalFromHub(userA, amount);
            vm.prank(userA);
            assetOFT_arb.approve(address(yzEnforcedComposer_arb), amount);
            
            SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, amount);
            
            uint256 gasBefore = gasleft();
            vm.prank(userA);
            yzEnforcedComposer_arb.depositAndSend(amount, sendParam, userA);
            uint256 gasAfter = gasleft();
            
            gasUsages[i] = gasBefore - gasAfter;
            
            // Gas usage should not scale linearly with amount
            // It should be relatively constant regardless of deposit size
            if (i > 0) {
                uint256 gasIncrease = gasUsages[i] - gasUsages[0];
                uint256 percentageIncrease = (gasIncrease * 100) / gasUsages[0];
                
                // Allow some increase due to data size, but not proportional to amount
                assertLt(percentageIncrease, 50, "Gas usage scaling too much with deposit amount");
            }
        }
        
        // Log performance data
        for (uint256 i = 0; i < depositAmounts.length; i++) {
            emit log_named_uint(
                string(abi.encodePacked("Deposit ", Strings.toString(depositAmounts[i]), " Gas")),
                gasUsages[i]
            );
        }
    }

    function test_PerformanceRegression_MultipleUsers() public {
        _setupTVLCap(10000 ether);
        
        address[] memory users = new address[](10);
        for (uint256 i = 0; i < users.length; i++) {
            users[i] = address(uint160(uint256(keccak256(abi.encodePacked("user", i)))));
            _setupUserCap(users[i], 1000 ether);
        }
        
        uint256 totalGasUsed = 0;
        
        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            uint256 amount = 100 ether;
            
            _fundLocalFromHub(user, amount);
            vm.prank(user);
            assetOFT_arb.approve(address(yzEnforcedComposer_arb), amount);
            
            SendParam memory sendParam = _buildHopParam(address(0), user, ARB_EID, amount);
            
            uint256 gasBefore = gasleft();
            vm.prank(user);
            yzEnforcedComposer_arb.depositAndSend(amount, sendParam, user);
            uint256 gasAfter = gasleft();
            
            uint256 gasUsed = gasBefore - gasAfter;
            totalGasUsed += gasUsed;
            
            // Each individual deposit should be within gas limits
            assertLt(gasUsed, GAS_LIMIT_THRESHOLD, "Individual deposit gas usage too high");
        }
        
        // Average gas per deposit should be reasonable
        uint256 avgGasPerDeposit = totalGasUsed / users.length;
        assertLt(avgGasPerDeposit, 300000, "Average deposit gas usage too high");
        
        emit log_named_uint("Total Gas for 10 Deposits", totalGasUsed);
        emit log_named_uint("Average Gas per Deposit", avgGasPerDeposit);
    }

    function test_PerformanceRegression_CapOperationsScaling() public {
        uint256 gasBefore;
        uint256 gasAfter;
        uint256 gasUsed;
        
        // Test batch operations scaling
        uint256[] memory userCounts = new uint256[](4);
        userCounts[0] = 5;
        userCounts[1] = 10;
        userCounts[2] = 20;
        userCounts[3] = 50;
        
        uint256[] memory gasUsages = new uint256[](4);
        
        for (uint256 idx = 0; idx < userCounts.length; idx++) {
            uint256 userCount = userCounts[idx];
            
            address[] memory users = new address[](userCount);
            uint256[] memory caps = new uint256[](userCount);
            
            for (uint256 i = 0; i < userCount; i++) {
                users[i] = address(uint160(uint256(keccak256(abi.encodePacked("user", i, idx)))));
                caps[i] = 100 ether;
            }
            
            gasBefore = gasleft();
            vm.prank(admin);
            yzEnforcedComposer_arb.batchSetUserCaps(users, caps);
            gasAfter = gasleft();
            
            gasUsages[idx] = gasAfter - gasBefore;
            
            // Gas usage should scale sub-linearly with user count
            if (idx > 0) {
                uint256 prevGas = gasUsages[idx - 1];
                uint256 currentGas = gasUsages[idx];
                uint256 userIncrease = userCounts[idx] - userCounts[idx - 1];
                
                // Gas increase should be less than proportional to user increase
                uint256 expectedGasIncrease = (prevGas * userIncrease) / userCounts[idx - 1];
                assertLe(currentGas - prevGas, expectedGasIncrease * 2, "Gas scaling too much with user count");
            }
        }
        
        // Log performance data
        for (uint256 i = 0; i < userCounts.length; i++) {
            emit log_named_uint(
                string(abi.encodePacked("BatchSetUserCaps ", Strings.toString(userCounts[i]), " Users Gas")),
                gasUsages[i]
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                        GAS OPTIMIZATION VALIDATION
    //////////////////////////////////////////////////////////////*/

    function test_GasOptimization_EventEmissions() public {
        _setupUserCap(userA, 1000 ether);
        _setupTVLCap(2000 ether);
        
        // Test that events are emitted efficiently
        uint256 gasBefore = gasleft();
        
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(1000 ether);
        
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(userA, 500 ether);
        
        vm.prank(admin);
        yzEnforcedComposer_arb.pauseDeposits();
        
        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;
        
        // Gas usage should be reasonable even with multiple events
        assertLt(gasUsed, 100000, "Event emissions too gas expensive");
        
        emit log_named_uint("Multiple Events Gas Used", gasUsed);
    }

    function test_GasOptimization_StorageAccess() public {
        _setupUserCap(userA, 1000 ether);
        _setupTVLCap(2000 ether);
        
        // Test that storage access is optimized
        uint256 gasBefore = gasleft();
        
        // Multiple read operations
        yzEnforcedComposer_arb.tvlCap();
        yzEnforcedComposer_arb.userDepositCap(userA);
        yzEnforcedComposer_arb.userDeposits(userA);
        yzEnforcedComposer_arb.depositsPaused();
        yzEnforcedComposer_arb.redemptionsPaused();
        
        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;
        
        // Storage reads should be efficient
        assertLt(gasUsed, 50000, "Storage access too gas expensive");
        
        emit log_named_uint("Multiple Storage Reads Gas Used", gasUsed);
    }

    function test_GasOptimization_CalldataEfficiency() public {
        _setupUserCap(userA, 1000 ether);
        _setupTVLCap(2000 ether);
        
        // Test that calldata processing is efficient
        uint256 gasBefore = gasleft();
        
        // Large calldata operation
        address[] memory users = new address[](20);
        uint256[] memory caps = new uint256[](20);
        
        for (uint256 i = 0; i < 20; i++) {
            users[i] = address(uint160(uint256(keccak256(abi.encodePacked("user", i)))));
            caps[i] = 100 ether;
        }
        
        vm.prank(admin);
        yzEnforcedComposer_arb.batchSetUserCaps(users, caps);
        
        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;
        
        // Large calldata should be processed efficiently
        assertLt(gasUsed, 200000, "Calldata processing too gas expensive");
        
        emit log_named_uint("Large Calldata Gas Used", gasUsed);
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
}