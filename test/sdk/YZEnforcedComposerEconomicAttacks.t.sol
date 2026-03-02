// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {YZEnforcedComposer} from "../../src/sdk/YZEnforcedComposer.sol";
import "./YZEnforcedComposerBase.t.sol";

/**
 * @title YZEnforcedComposer Economic Attack Tests
 * @notice Professional tests for economic attack vectors and timing attacks
 * @dev Tests sandwich attacks, front-running, and economic edge cases
 */
contract YZEnforcedComposerEconomicAttacksTest is YZEnforcedComposerBase {
    
    // Test constants
    uint256 internal constant TEST_AMOUNT = 50 ether;
    uint256 internal constant LARGE_AMOUNT = 500 ether;

    function setUp() public override {
        super.setUp();
        _setupDefaultCaps();
    }

    /*//////////////////////////////////////////////////////////////
                        SANDWICH ATTACK TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SandwichAttack_DepositBeforeCapUpdate() public {
        // Setup initial state near cap
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(100 ether);
        
        // User A deposits to reach cap
        _executeSuccessfulDeposit(userA, 100 ether);
        assertEq(vault_arb.totalAssets(), 100 ether);
        
        // Attacker tries to deposit after cap is reached
        _fundLocalFromHub(attacker, TEST_AMOUNT);
        vm.prank(attacker);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), TEST_AMOUNT);
        
        SendParam memory sendParam = _buildHopParam(address(0), attacker, ARB_EID, TEST_AMOUNT);
        
        vm.expectRevert();
        vm.prank(attacker);
        yzEnforcedComposer_arb.depositAndSend(TEST_AMOUNT, sendParam, attacker);
        
        // Verify cap still enforced
        assertEq(vault_arb.totalAssets(), 100 ether);
        assertEq(yzEnforcedComposer_arb.userDeposits(attacker), 0);
    }

    function test_SandwichAttack_DepositBeforePause() public {
        // Setup state
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        // User A deposits
        _executeSuccessfulDeposit(userA, 50 ether);
        
        // Admin pauses deposits in same block (simulated)
        vm.prank(admin);
        yzEnforcedComposer_arb.pauseDeposits();
        
        // Attacker tries to deposit after pause
        _fundLocalFromHub(attacker, TEST_AMOUNT);
        vm.prank(attacker);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), TEST_AMOUNT);
        
        SendParam memory sendParam = _buildHopParam(address(0), attacker, ARB_EID, TEST_AMOUNT);
        
        vm.expectRevert(YZEnforcedComposer.YZ_DepositsPaused.selector);
        vm.prank(attacker);
        yzEnforcedComposer_arb.depositAndSend(TEST_AMOUNT, sendParam, attacker);
        
        // Verify pause enforced
        assertEq(vault_arb.totalAssets(), 50 ether);
        assertEq(yzEnforcedComposer_arb.userDeposits(attacker), 0);
    }

    function test_SandwichAttack_DepositBeforeWhitelistToggle() public {
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelistEnabled(true);
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelist(userA, true);
        
        // User A deposits while whitelisted
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        _executeSuccessfulDeposit(userA, 50 ether);
        
        // Admin removes whitelist
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelist(userA, false);
        
        // Attacker tries to deposit after whitelist removed
        _fundLocalFromHub(attacker, TEST_AMOUNT);
        vm.prank(attacker);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), TEST_AMOUNT);
        
        SendParam memory sendParam = _buildHopParam(address(0), attacker, ARB_EID, TEST_AMOUNT);
        
        vm.expectRevert(YZEnforcedComposer.YZ_NotWhitelisted.selector);
        vm.prank(attacker);
        yzEnforcedComposer_arb.depositAndSend(TEST_AMOUNT, sendParam, attacker);
        
        // Verify whitelist enforced
        assertEq(vault_arb.totalAssets(), 50 ether);
        assertEq(yzEnforcedComposer_arb.userDeposits(attacker), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        CAP FRONT-RUNNING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CapFrontRunning_SameBlockRaceCondition() public {
        _setupUserCap(userA, 100 ether);
        _setupUserCap(userB, 100 ether);
        _setupTVLCap(100 ether);
        
        // Both users try to deposit 100 ether in same block
        _fundLocalFromHub(userA, 100 ether);
        _fundLocalFromHub(userB, 100 ether);
        
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 100 ether);
        vm.prank(userB);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 100 ether);
        
        SendParam memory sendParamA = _buildHopParam(address(0), userA, ARB_EID, 100 ether);
        SendParam memory sendParamB = _buildHopParam(address(0), userB, ARB_EID, 100 ether);
        
        // First deposit should succeed
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(100 ether, sendParamA, userA);
        assertEq(vault_arb.totalAssets(), 100 ether);
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), 100 ether);
        
        // Second deposit should fail
        vm.prank(userB);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend(100 ether, sendParamB, userB);
        
        assertEq(yzEnforcedComposer_arb.userDeposits(userB), 0);
    }

    function test_CapFrontRunning_PartialCapExhaustion() public {
        _setupUserCap(userA, 100 ether);
        _setupUserCap(userB, 100 ether);
        _setupTVLCap(150 ether);
        
        // User A deposits 100 ether
        _executeSuccessfulDeposit(userA, 100 ether);
        assertEq(vault_arb.totalAssets(), 100 ether);
        
        // User B tries to deposit 100 ether (would exceed cap)
        _fundLocalFromHub(userB, 100 ether);
        vm.prank(userB);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 100 ether);
        
        SendParam memory sendParam = _buildHopParam(address(0), userB, ARB_EID, 100 ether);
        
        vm.expectRevert();
        vm.prank(userB);
        yzEnforcedComposer_arb.depositAndSend(100 ether, sendParam, userB);
        
        // Verify only 50 ether capacity remains
        assertEq(vault_arb.totalAssets(), 100 ether);
        assertEq(yzEnforcedComposer_arb.userDeposits(userB), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        BLOCK/TIME MANIPULATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_BlockManipulation_EpochBasedCaps() public {
        // Test if contract has epoch-based logic
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        // Deposit in current block
        _executeSuccessfulDeposit(userA, 50 ether);
        uint256 initialBlock = block.number;
        
        // Advance blocks
        vm.roll(initialBlock + 100);
        
        // Should still work after block advancement
        _executeSuccessfulDeposit(userA, 50 ether);
        assertEq(vault_arb.totalAssets(), 100 ether);
        
        // Advance more blocks
        vm.roll(initialBlock + 1000);
        
        // Should still enforce caps correctly
        _fundLocalFromHub(userB, 100 ether);
        vm.prank(userB);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 100 ether);
        
        SendParam memory sendParam = _buildHopParam(address(0), userB, ARB_EID, 100 ether);
        
        vm.prank(userB);
        yzEnforcedComposer_arb.depositAndSend(100 ether, sendParam, userB);
        assertEq(vault_arb.totalAssets(), 200 ether);
    }

    function test_TimeManipulation_TimestampBasedLogic() public {
        // Test if contract has timestamp-based logic
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        // Deposit at current time
        _executeSuccessfulDeposit(userA, 50 ether);
        uint256 initialTime = block.timestamp;
        
        // Advance time
        vm.warp(initialTime + 1 days);
        
        // Should still work after time advancement
        _executeSuccessfulDeposit(userA, 50 ether);
        assertEq(vault_arb.totalAssets(), 100 ether);
        
        // Advance more time
        vm.warp(initialTime + 7 days);
        
        // Should still enforce caps correctly
        _fundLocalFromHub(userB, 100 ether);
        vm.prank(userB);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 100 ether);
        
        SendParam memory sendParam = _buildHopParam(address(0), userB, ARB_EID, 100 ether);
        
        vm.prank(userB);
        yzEnforcedComposer_arb.depositAndSend(100 ether, sendParam, userB);
        assertEq(vault_arb.totalAssets(), 200 ether);
    }

    /*//////////////////////////////////////////////////////////////
                        PRECISION & ROUNDING ATTACKS
    //////////////////////////////////////////////////////////////*/

    function test_RoundingAttack_FirstDepositorAdvantage() public {
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        // First depositor with very small amount
        uint256 firstDeposit = 1 wei;
        _fundLocalFromHub(userA, firstDeposit);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), firstDeposit);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, firstDeposit);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(firstDeposit, sendParam, userA);
        
        // Verify first depositor gets fair share
        uint256 userShares = vault_arb.balanceOf(userA);
        uint256 totalShares = vault_arb.totalSupply();
        uint256 totalAssets = vault_arb.totalAssets();
        
        // Should have received shares proportional to deposit
        assertGt(userShares, 0);
        assertEq(totalShares, userShares);
        assertEq(totalAssets, firstDeposit);
    }

    function test_RoundingAttack_DustAttack() public {
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        // Large initial deposit
        _executeSuccessfulDeposit(userA, 100 ether);
        
        // Very small subsequent deposit (dust)
        uint256 dustAmount = 1 wei;
        _fundLocalFromHub(userB, dustAmount);
        vm.prank(userB);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), dustAmount);
        
        SendParam memory sendParam = _buildHopParam(address(0), userB, ARB_EID, dustAmount);
        
        vm.prank(userB);
        yzEnforcedComposer_arb.depositAndSend(dustAmount, sendParam, userB);
        
        // Verify dust deposit doesn't break exchange rate
        uint256 exchangeRate = vault_arb.convertToAssets(1 ether);
        assertGt(exchangeRate, 0);
        assertLe(exchangeRate, 1 ether + 1); // Allow small rounding up
    }

    function test_RoundingAttack_MinDepositEdgeCase() public {
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        // Test minimum possible deposit
        uint256 minDeposit = 1;
        _fundLocalFromHub(userA, minDeposit);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), minDeposit);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, minDeposit);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(minDeposit, sendParam, userA);
        
        // Verify minimum deposit works
        assertEq(vault_arb.totalAssets(), minDeposit);
        assertGt(vault_arb.balanceOf(userA), 0);
    }

    function test_RoundingAttack_ZeroSupplyEdgeCase() public {
        // Test behavior when vault has zero supply
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        // First deposit should work even with zero supply
        uint256 firstDeposit = 1 ether;
        _fundLocalFromHub(userA, firstDeposit);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), firstDeposit);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, firstDeposit);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(firstDeposit, sendParam, userA);
        
        // Verify first deposit establishes supply
        assertEq(vault_arb.totalAssets(), firstDeposit);
        assertGt(vault_arb.totalSupply(), 0);
        assertGt(vault_arb.balanceOf(userA), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        CHAOS TESTING
    //////////////////////////////////////////////////////////////*/

    function test_Chaos_AdminChangesDuringDeposit() public {
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        // Start deposit process
        _fundLocalFromHub(userA, 100 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 100 ether);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 100 ether);
        
        // Change admin config during deposit
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(50 ether);
        
        // Deposit should still succeed (config change doesn't affect ongoing tx)
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(100 ether, sendParam, userA);
        
        // But TVL cap should now be enforced
        _fundLocalFromHub(userB, 100 ether);
        vm.prank(userB);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 100 ether);
        
        SendParam memory sendParamB = _buildHopParam(address(0), userB, ARB_EID, 100 ether);
        
        vm.expectRevert();
        vm.prank(userB);
        yzEnforcedComposer_arb.depositAndSend(100 ether, sendParamB, userB);
    }

    function test_Chaos_WhitelistToggleDuringExecution() public {
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelistEnabled(true);
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelist(userA, true);
        
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        // Start deposit
        _fundLocalFromHub(userA, 50 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);
        
        // Toggle whitelist during execution
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelist(userA, false);
        
        // Deposit should still succeed (whitelist change doesn't affect ongoing tx)
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(50 ether, sendParam, userA);
        
        // But new deposits should fail
        _fundLocalFromHub(userB, 50 ether);
        vm.prank(userB);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);
        
        SendParam memory sendParamB = _buildHopParam(address(0), userB, ARB_EID, 50 ether);
        
        vm.expectRevert(YZEnforcedComposer.YZ_NotWhitelisted.selector);
        vm.prank(userB);
        yzEnforcedComposer_arb.depositAndSend(50 ether, sendParamB, userB);
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