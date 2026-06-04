// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {YZEnforcedComposer} from "../../src/YZEnforcedComposer.sol";
import "../unit/YZEnforcedComposerBase.t.sol";

/**
 * @title YZEnforcedComposer Economic Simulation
 * @notice Professional economic simulation for protocol-level edge cases
 * @dev Simulates real-world economic attack scenarios that invariants alone cannot catch
 */
contract YZEnforcedComposerEconomicSimulation is YZEnforcedComposerBase {
    // Economic simulation parameters
    uint256 internal constant SIMULATION_CYCLES = 1000;
    uint256 internal constant WHALE_THRESHOLD = 1000 ether;
    uint256 internal constant CAP_CHANGE_FREQUENCY = 10;
    uint256 internal constant WHITELIST_TOGGLE_FREQUENCY = 20;
    uint256 internal constant GAS_GRIEF_MULTIPLIER = 3;
    uint256 internal constant MAX_TEST_AMOUNT = 20000 ether;

    // Simulation state tracking
    struct EconomicState {
        uint256 totalDeposits;
        uint256 totalRedemptions;
        uint256 netTVL;
        uint256 exchangeRate;
        uint256 capChanges;
        uint256 whitelistToggles;
        uint256 failedOperations;
        uint256 successfulOperations;
        uint256 gasSpent;
    }

    EconomicState internal economicState;

    function setUp() public override {
        super.setUp();
        _setupDefaultCaps();
        _resetEconomicState();
    }

    /*//////////////////////////////////////////////////////////////
                        ECONOMIC DEGRADATION SIMULATIONS
    //////////////////////////////////////////////////////////////*/

    function test_EconomicSimulation_DepositRedeemCycles() public {
        // Simulate rapid deposit/redeem cycles to test economic degradation
        address whale = userA;
        address retail = userB;

        _setupUserCap(whale, 10000 ether);
        _setupUserCap(retail, 100 ether);
        _setupTVLCap(50000 ether);

        for (uint256 i = 0; i < SIMULATION_CYCLES; i++) {
            // Randomize operation type and amount
            uint256 operation = uint256(keccak256(abi.encodePacked(block.timestamp, i))) % 4;
            address user = (i % 2 == 0) ? whale : retail;
            uint256 amount = _getSimulationAmount(user, operation);

            if (operation == 0) {
                _simulateDeposit(user, amount);
            } else if (operation == 1) {
                _simulateRedeem(user, amount);
            } else if (operation == 2) {
                _simulateCapChange();
            } else {
                _simulateWhitelistToggle(user);
            }

            // Check for economic degradation
            _checkEconomicDegradation(i);

            // Periodic state validation
            if (i % 100 == 0) {
                _validateEconomicState();
            }
        }

        // Final economic health check
        _finalEconomicHealthCheck();
    }

    function test_EconomicSimulation_WhaleSandwiching() public {
        // Simulate whale sandwiching attacks on cap boundaries
        address whale = userA;
        address victim = userB;

        _setupUserCap(whale, 5000 ether);
        _setupUserCap(victim, 1000 ether);
        _setupTVLCap(1000 ether);

        // Set initial TVL close to cap
        _executeSuccessfulDeposit(victim, 950 ether);

        for (uint256 i = 0; i < 50; i++) {
            // Whale tries to push cap over limit
            uint256 whaleAmount = 100 ether;
            _fundLocalFromHub(whale, whaleAmount);

            // Simulate race condition where whale deposits just before cap enforcement
            vm.prank(whale);
            assetOFT_arb.approve(address(yzEnforcedComposer_arb), whaleAmount);

            SendParam memory sendParam = _buildHopParam(address(0), whale, ARB_EID, whaleAmount);

            // This should fail due to cap
            vm.expectRevert(
                abi.encodeWithSelector(YZEnforcedComposer.YZ_TVLCapExceeded.selector, 950 ether, 100 ether, 1000 ether)
            );
            vm.prank(whale);
            yzEnforcedComposer_arb.depositAndSend(whaleAmount, sendParam, whale);

            economicState.failedOperations++;

            // Victim tries to redeem
            uint256 victimShares = vault_arb.balanceOf(victim);
            if (victimShares > 0) {
                vm.prank(victim);
                vault_arb.approve(address(yzEnforcedComposer_arb), victimShares);

                SendParam memory redeemParam = _buildHopParam(address(0), victim, ARB_EID, victimShares);

                vm.prank(victim);
                yzEnforcedComposer_arb.redeemAndSend(victimShares, redeemParam, victim);

                economicState.successfulOperations++;

                // Replenish the TVL back to 950 ether for the next iteration
                _executeSuccessfulDeposit(victim, 950 ether);
            }
        }
    }

    function test_EconomicSimulation_CapEdgeGriefing() public {
        // Simulate cap-edge griefing where admin changes cap during operations
        address user = userA;
        _setupUserCap(user, 10000 ether);

        // Start with high cap
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(10000 ether);

        // User deposits large amount
        _executeSuccessfulDeposit(user, 5000 ether);

        for (uint256 i = 0; i < 100; i++) {
            // Admin griefs by rapidly changing cap
            if (i % 2 == 0) {
                vm.prank(admin);
                yzEnforcedComposer_arb.setTVLCap(4000 ether); // Below current TVL
            } else {
                vm.prank(admin);
                yzEnforcedComposer_arb.setTVLCap(6000 ether); // Above current TVL
            }

            economicState.capChanges++;

            // User tries to deposit during cap changes
            uint256 depositAmount = 100 ether;
            _fundLocalFromHub(user, depositAmount);
            vm.prank(user);
            assetOFT_arb.approve(address(yzEnforcedComposer_arb), depositAmount);

            SendParam memory sendParam = _buildHopParam(address(0), user, ARB_EID, depositAmount);

            if (yzEnforcedComposer_arb.tvlCap() <= vault_arb.totalAssets()) {
                // Should fail due to cap
                uint256 currentTVL = vault_arb.totalAssets();
                uint256 tvlCap = yzEnforcedComposer_arb.tvlCap();
                vm.expectRevert(
                    abi.encodeWithSelector(
                        YZEnforcedComposer.YZ_TVLCapExceeded.selector, currentTVL, depositAmount, tvlCap
                    )
                );
                vm.prank(user);
                yzEnforcedComposer_arb.depositAndSend(depositAmount, sendParam, user);
                economicState.failedOperations++;
            } else {
                // Should succeed
                vm.prank(user);
                yzEnforcedComposer_arb.depositAndSend(depositAmount, sendParam, user);
                economicState.successfulOperations++;

                // Assert that TVL is within cap when deposit succeeds
                assertLe(vault_arb.totalAssets(), yzEnforcedComposer_arb.tvlCap(), "TVL exceeded cap on success");
            }
        }
    }

    function test_EconomicSimulation_GasGriefingCrossChain() public {
        // Simulate gas griefing attacks on cross-chain operations
        address attacker = userA;
        address victim = userB;

        _setupUserCap(attacker, 1000 ether);
        _setupUserCap(victim, 10000 ether);
        _setupTVLCap(20000 ether);

        // Attacker performs expensive operations to increase gas costs
        for (uint256 i = 0; i < 50; i++) {
            // Attacker sends many small deposits to fragment state
            uint256 smallAmount = 1 ether;
            _executeSuccessfulDeposit(attacker, smallAmount);

            // Attacker changes caps frequently
            vm.prank(admin);
            yzEnforcedComposer_arb.setTVLCap((i % 2 == 0) ? 15000 ether : 25000 ether);

            economicState.capChanges++;
            economicState.gasSpent += gasleft();

            // Victim tries to perform normal operation
            uint256 victimAmount = 50 ether;
            _fundLocalFromHub(victim, victimAmount);
            vm.prank(victim);
            assetOFT_arb.approve(address(yzEnforcedComposer_arb), victimAmount);

            SendParam memory sendParam = _buildHopParam(address(0), victim, ARB_EID, victimAmount);

            uint256 gasBefore = gasleft();
            vm.prank(victim);
            yzEnforcedComposer_arb.depositAndSend(victimAmount, sendParam, victim);
            uint256 gasUsed = gasBefore - gasleft();

            economicState.gasSpent += gasUsed;
            economicState.successfulOperations++;

            // Check for gas griefing impact
            _checkGasGriefingImpact(gasUsed);
        }
    }

    function test_EconomicSimulation_SharePriceOscillation() public {
        // Simulate share price oscillation attacks
        address whale = userA;

        _setupUserCap(whale, type(uint256).max);
        _setupTVLCap(50000 ether);

        // Initial deposit to establish baseline
        _executeSuccessfulDeposit(whale, 1000 ether);
        uint256 initialExchangeRate = vault_arb.convertToAssets(1 ether);

        for (uint256 i = 0; i < 200; i++) {
            // Whale performs large deposits and redemptions to oscillate price
            uint256 operation = i % 3;

            if (operation == 0) {
                // Large deposit
                _executeSuccessfulDeposit(whale, 500 ether);
            } else if (operation == 1) {
                // Large redemption
                uint256 shares = vault_arb.balanceOf(whale);
                if (shares > 0) {
                    uint256 redeemAmount = shares / 2;
                    vm.prank(whale);
                    vault_arb.approve(address(yzEnforcedComposer_arb), redeemAmount);

                    SendParam memory redeemParam = _buildHopParam(address(0), whale, ARB_EID, redeemAmount);

                    vm.prank(whale);
                    yzEnforcedComposer_arb.redeemAndSend(redeemAmount, redeemParam, whale);
                }
            } else {
                // Small normal operation
                _executeSuccessfulDeposit(whale, 10 ether);
            }

            // Check for price manipulation
            uint256 currentExchangeRate = vault_arb.convertToAssets(1 ether);
            uint256 rateChange = currentExchangeRate > initialExchangeRate
                ? currentExchangeRate - initialExchangeRate
                : initialExchangeRate - currentExchangeRate;

            // Exchange rate should not oscillate wildly
            uint256 maxAllowedChange = (initialExchangeRate * 10) / 100; // 10% max change

            assertLe(rateChange, maxAllowedChange, "Share price oscillation attack detected");

            // Update baseline periodically
            if (i % 50 == 0) {
                initialExchangeRate = currentExchangeRate;
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                        ADVERSARIAL ECONOMIC ATTACKS
    //////////////////////////////////////////////////////////////*/

    function test_AdversarialEconomic_WhaleFrontRunning() public {
        // Simulate whale front-running smaller deposits
        address whale = userA;
        address smallUser = userB;

        _setupUserCap(whale, 5000 ether);
        _setupUserCap(smallUser, 50 ether);
        _setupTVLCap(1000 ether);

        // Small user tries to deposit
        _fundLocalFromHub(smallUser, 50 ether);
        vm.prank(smallUser);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);

        SendParam memory smallSendParam = _buildHopParam(address(0), smallUser, ARB_EID, 50 ether);

        // Whale front-runs with larger deposit (960 ether)
        _fundLocalFromHub(whale, 960 ether);
        vm.prank(whale);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 960 ether);

        SendParam memory whaleSendParam = _buildHopParam(address(0), whale, ARB_EID, 960 ether);

        // Whale should succeed, small user should fail due to cap
        vm.prank(whale);
        yzEnforcedComposer_arb.depositAndSend(960 ether, whaleSendParam, whale);

        vm.expectRevert(
            abi.encodeWithSelector(YZEnforcedComposer.YZ_TVLCapExceeded.selector, 960 ether, 50 ether, 1000 ether)
        );
        vm.prank(smallUser);
        yzEnforcedComposer_arb.depositAndSend(50 ether, smallSendParam, smallUser);

        // Verify cap enforcement worked correctly
        assertEq(vault_arb.totalAssets(), 960 ether, "Cap not enforced correctly");
    }

    function test_AdversarialEconomic_RetryManipulation() public {
        // Simulate manipulation of retry mechanisms
        address user = userA;
        _setupUserCap(user, 1000 ether);
        _setupTVLCap(2000 ether);

        // Mock LayerZero failure to trigger retry
        _mockLayerZeroRevert();

        _fundLocalFromHub(user, 500 ether);
        vm.deal(user, 10 ether);

        vm.prank(user);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 500 ether);

        SendParam memory sendParam = _buildHopParam(address(0), user, POL_EID, 500 ether);

        // First attempt should fail
        vm.prank(user);
        try yzEnforcedComposer_arb.depositAndSend{value: 1 ether}(500 ether, sendParam, user) {
            fail("First attempt should fail");
        } catch {}

        // Reset mock for retry
        _resetLayerZeroMock();

        // Retry should succeed
        vm.prank(user);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 500 ether);

        vm.prank(user);
        yzEnforcedComposer_arb.depositAndSend{value: 1 ether}(500 ether, sendParam, user);

        // Verify no double credit
        assertEq(vault_arb.totalAssets(), 500 ether, "Double credit detected in retry");
    }

    function test_AdversarialEconomic_CapExhaustionAttack() public {
        // Simulate attack where multiple users try to exhaust cap simultaneously
        address[] memory users = new address[](10);
        for (uint256 i = 0; i < 10; i++) {
            users[i] = address(uint160(uint256(keccak256(abi.encodePacked("user", i)))));
            _setupUserCap(users[i], 100 ether);
        }

        _setupTVLCap(500 ether);

        uint256 successfulDeposits = 0;
        uint256 failedDeposits = 0;

        // All users try to deposit simultaneously
        for (uint256 i = 0; i < 10; i++) {
            _fundLocalFromHub(users[i], 100 ether);
            vm.prank(users[i]);
            assetOFT_arb.approve(address(yzEnforcedComposer_arb), 100 ether);

            SendParam memory sendParam = _buildHopParam(address(0), users[i], ARB_EID, 100 ether);

            if (successfulDeposits < 5) {
                // First 5 should succeed
                vm.prank(users[i]);
                yzEnforcedComposer_arb.depositAndSend(100 ether, sendParam, users[i]);
                successfulDeposits++;
            } else {
                // Remaining should fail
                vm.expectRevert(
                    abi.encodeWithSelector(
                        YZEnforcedComposer.YZ_TVLCapExceeded.selector, 500 ether, 100 ether, 500 ether
                    )
                );
                vm.prank(users[i]);
                yzEnforcedComposer_arb.depositAndSend(100 ether, sendParam, users[i]);
                failedDeposits++;
            }
        }

        // Verify cap enforcement
        assertEq(successfulDeposits, 5, "Incorrect number of successful deposits");
        assertEq(failedDeposits, 5, "Incorrect number of failed deposits");
        assertEq(vault_arb.totalAssets(), 500 ether, "Cap not enforced correctly");
    }

    /*//////////////////////////////////////////////////////////////
                            ECONOMIC HEALTH CHECKS
    //////////////////////////////////////////////////////////////*/

    function _checkEconomicDegradation(uint256 cycle) internal {
        uint256 currentTVL = vault_arb.totalAssets();
        uint256 currentExchangeRate = vault_arb.convertToAssets(1 ether);

        // Check for exchange rate degradation
        assertGe(currentExchangeRate, 0.99 ether, "Exchange rate degradation detected");
        assertLe(currentExchangeRate, 1.01 ether, "Exchange rate inflation detected");

        economicState.netTVL = currentTVL;
        economicState.exchangeRate = currentExchangeRate;
    }

    function _validateEconomicState() internal {
        uint256 totalShares = vault_arb.totalSupply();
        uint256 totalAssets = vault_arb.totalAssets();

        // Validate share/asset consistency
        if (totalShares > 0) {
            uint256 shareValue = vault_arb.convertToAssets(totalShares);
            uint256 diff = totalAssets > shareValue ? totalAssets - shareValue : shareValue - totalAssets;
            assertLe(diff, 1 ether, "Share/asset inconsistency detected");
        }

        // Validate cap enforcement
        uint256 tvlCap = yzEnforcedComposer_arb.tvlCap();
        if (tvlCap > 0) {
            assertLe(totalAssets, tvlCap, "Cap enforcement failed");
        }
    }

    function _finalEconomicHealthCheck() internal {
        uint256 finalTVL = vault_arb.totalAssets();
        uint256 finalExchangeRate = vault_arb.convertToAssets(1 ether);

        // Final health metrics
        assertGe(finalTVL, economicState.totalDeposits - economicState.totalRedemptions, "Final TVL inconsistent");
        assertGe(finalExchangeRate, 0.99 ether, "Final exchange rate degraded");
        assertLe(finalExchangeRate, 1.01 ether, "Final exchange rate inflated");

        // Success rate should be reasonable
        uint256 totalOperations = economicState.successfulOperations + economicState.failedOperations;
        if (totalOperations > 0) {
            uint256 successRate = (economicState.successfulOperations * 100) / totalOperations;
            assertGe(successRate, 20, "Success rate too low - economic degradation");
        }
    }

    function _checkSandwichAttackPrevention() internal {
        uint256 currentTVL = vault_arb.totalAssets();
        uint256 tvlCap = yzEnforcedComposer_arb.tvlCap();

        // Cap should never be exceeded
        if (tvlCap > 0) {
            assertLe(currentTVL, tvlCap, "Sandwich attack bypassed cap");
        }
    }

    function _checkCapEdgeGriefing() internal {
        uint256 currentTVL = vault_arb.totalAssets();
        uint256 tvlCap = yzEnforcedComposer_arb.tvlCap();

        // Even with rapid cap changes, TVL should never exceed any cap value
        if (tvlCap > 0 && currentTVL > tvlCap) {
            assertTrue(false, "Cap edge griefing succeeded");
        }
    }

    function _checkGasGriefingImpact(uint256 gasUsed) internal {
        // Gas usage should not increase dramatically due to attacker actions
        // Allow some variance but not exponential growth
        assertLe(gasUsed, 500000, "Gas griefing attack detected - excessive gas usage");
    }

    /*//////////////////////////////////////////////////////////////
                            SIMULATION HELPERS
    //////////////////////////////////////////////////////////////*/

    function _simulateDeposit(address user, uint256 amount) internal {
        _fundLocalFromHub(user, amount);
        vm.prank(user);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), amount);

        SendParam memory sendParam = _buildHopParam(address(0), user, ARB_EID, amount);
        vm.prank(user);
        try yzEnforcedComposer_arb.depositAndSend(amount, sendParam, user) {
            economicState.successfulOperations++;
            economicState.totalDeposits += amount;
        } catch {
            economicState.failedOperations++;
        }
    }

    function _simulateRedeem(address user, uint256 amount) internal {
        uint256 shares = vault_arb.balanceOf(user);
        if (shares == 0) return;

        uint256 redeemShares = (amount > shares) ? shares : amount;

        vm.prank(user);
        vault_arb.approve(address(yzEnforcedComposer_arb), redeemShares);

        SendParam memory redeemParam = _buildHopParam(address(0), user, ARB_EID, redeemShares);
        vm.prank(user);
        try yzEnforcedComposer_arb.redeemAndSend(redeemShares, redeemParam, user) {
            economicState.successfulOperations++;
            economicState.totalRedemptions += redeemShares;
        } catch {
            economicState.failedOperations++;
        }
    }

    function _simulateCapChange() internal {
        uint256 newCap = uint256(keccak256(abi.encodePacked(block.timestamp))) % 10000 ether;
        newCap = newCap + 1000 ether; // Ensure minimum cap

        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(newCap);
        economicState.capChanges++;
    }

    function _simulateWhitelistToggle(address user) internal {
        bool currentStatus = yzEnforcedComposer_arb.whitelist(user);
        bool newStatus = !currentStatus;

        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelist(user, newStatus);
        economicState.whitelistToggles++;
    }

    function _getSimulationAmount(address user, uint256 operation) internal view returns (uint256) {
        uint256 random = uint256(keccak256(abi.encodePacked(block.timestamp, user, operation)));

        if (user == userA) {
            // Whale amounts
            return (random % 1000 ether) + 1 ether;
        } else {
            // Retail amounts
            return (random % 100 ether) + 1 ether;
        }
    }

    function _resetEconomicState() internal {
        economicState.totalDeposits = 0;
        economicState.totalRedemptions = 0;
        economicState.netTVL = 0;
        economicState.exchangeRate = 1 ether;
        economicState.capChanges = 0;
        economicState.whitelistToggles = 0;
        economicState.failedOperations = 0;
        economicState.successfulOperations = 0;
        economicState.gasSpent = 0;
    }

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

    /*//////////////////////////////////////////////////////////////
                        MOCK FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _mockLayerZeroRevert() internal {
        vm.mockCallRevert(
            address(shareOFT_arb), abi.encodeWithSelector(shareOFT_arb.send.selector), abi.encode("LayerZero revert")
        );
    }

    function _resetLayerZeroMock() internal {
        vm.clearMockedCalls();
    }
}
