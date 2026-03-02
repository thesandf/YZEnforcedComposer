// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {YZEnforcedComposer} from "../../src/sdk/YZEnforcedComposer.sol";
import "./YZEnforcedComposerBase.t.sol";

/**
 * @title YZEnforcedComposer Stateful Fuzz Tests
 * @notice Professional stateful fuzzing tests using Foundry's invariant testing
 * @dev Tests complex state transitions and property-based invariants
 */
contract YZEnforcedComposerStatefulFuzzTest is YZEnforcedComposerBase {
    
    // Fuzz test constants
    uint256 internal constant MAX_FUZZ_ITERATIONS = 100;
    uint256 internal constant MAX_FUZZ_AMOUNT = 1000 ether;
    uint256 internal constant MIN_FUZZ_AMOUNT = 1 ether;

    // State tracking for fuzzing
    struct FuzzState {
        uint256 totalDeposits;
        uint256 totalRedemptions;
        uint256 activeUsers;
        uint256 pausedDeposits;
        uint256 pausedRedemptions;
        uint256 whitelistEnabled;
    }

    FuzzState internal fuzzState;

    function setUp() public override {
        super.setUp();
        _setupDefaultCaps();
        _resetFuzzState();
    }

    /*//////////////////////////////////////////////////////////////
                        STATEFUL FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function test_StatefulFuzz_RandomOperations() public {
        // Run multiple random operations
        for (uint256 i = 0; i < MAX_FUZZ_ITERATIONS; i++) {
            uint256 operation = uint256(keccak256(abi.encodePacked(block.timestamp, i))) % 10;
            
            if (operation == 0) {
                _fuzzDeposit();
            } else if (operation == 1) {
                _fuzzRedeem();
            } else if (operation == 2) {
                _fuzzSetTVLCap();
            } else if (operation == 3) {
                _fuzzSetUserCap();
            } else if (operation == 4) {
                _fuzzPauseDeposits();
            } else if (operation == 5) {
                _fuzzPauseRedemptions();
            } else if (operation == 6) {
                _fuzzSetWhitelist();
            } else if (operation == 7) {
                _fuzzEmergencyWithdraw();
            } else if (operation == 8) {
                _fuzzAdminChanges();
            } else {
                _fuzzViewOperations();
            }
            
            // Check invariants after each operation
            _checkInvariants();
        }
    }

    function test_StatefulFuzz_MultipleUsers() public {
        address[] memory users = new address[](5);
        for (uint256 i = 0; i < users.length; i++) {
            users[i] = address(uint160(uint256(keccak256(abi.encodePacked("fuzzUser", i)))));
        }
        
        // Run operations across multiple users
        for (uint256 i = 0; i < MAX_FUZZ_ITERATIONS; i++) {
            address user = users[i % users.length];
            uint256 operation = uint256(keccak256(abi.encodePacked(block.timestamp, i, user))) % 5;
            
            if (operation == 0) {
                _fuzzUserDeposit(user);
            } else if (operation == 1) {
                _fuzzUserRedeem(user);
            } else if (operation == 2) {
                _fuzzUserCapChange(user);
            } else if (operation == 3) {
                _fuzzUserWhitelistChange(user);
            } else {
                _fuzzUserViewOperations(user);
            }
            
            _checkMultiUserInvariants(users);
        }
    }

    function test_StatefulFuzz_CapManagement() public {
        // Test cap management under various conditions
        for (uint256 i = 0; i < MAX_FUZZ_ITERATIONS; i++) {
            uint256 operation = uint256(keccak256(abi.encodePacked(block.timestamp, i, "cap"))) % 6;
            
            if (operation == 0) {
                _fuzzSetTVLCap();
            } else if (operation == 1) {
                _fuzzBatchSetUserCaps();
            } else if (operation == 2) {
                _fuzzCapBoundaryTesting();
            } else if (operation == 3) {
                _fuzzCapRaceConditions();
            } else if (operation == 4) {
                _fuzzCapConsistency();
            } else {
                _fuzzCapEdgeCases();
            }
            
            _checkCapInvariants();
        }
    }

    function test_StatefulFuzz_PauseControl() public {
        // Test pause controls under various conditions
        for (uint256 i = 0; i < MAX_FUZZ_ITERATIONS; i++) {
            uint256 operation = uint256(keccak256(abi.encodePacked(block.timestamp, i, "pause"))) % 8;
            
            if (operation == 0) {
                _fuzzPauseDeposits();
            } else if (operation == 1) {
                _fuzzUnpauseDeposits();
            } else if (operation == 2) {
                _fuzzPauseRedemptions();
            } else if (operation == 3) {
                _fuzzUnpauseRedemptions();
            } else if (operation == 4) {
                _fuzzPauseAll();
            } else if (operation == 5) {
                _fuzzUnpauseAll();
            } else if (operation == 6) {
                _fuzzPauseRaceConditions();
            } else {
                _fuzzPauseEdgeCases();
            }
            
            _checkPauseInvariants();
        }
    }

    function test_StatefulFuzz_WhitelistManagement() public {
        // Test whitelist management under various conditions
        address[] memory users = new address[](10);
        for (uint256 i = 0; i < users.length; i++) {
            users[i] = address(uint160(uint256(keccak256(abi.encodePacked("whitelistUser", i)))));
        }
        
        for (uint256 i = 0; i < MAX_FUZZ_ITERATIONS; i++) {
            uint256 operation = uint256(keccak256(abi.encodePacked(block.timestamp, i, "whitelist"))) % 6;
            
            if (operation == 0) {
                _fuzzSetWhitelistEnabled();
            } else if (operation == 1) {
                _fuzzSetWhitelist(users[i % users.length]);
            } else if (operation == 2) {
                _fuzzBatchSetWhitelist(users);
            } else if (operation == 3) {
                _fuzzWhitelistRaceConditions();
            } else if (operation == 4) {
                _fuzzWhitelistEdgeCases();
            } else {
                _fuzzWhitelistConsistency();
            }
            
            _checkWhitelistInvariants(users);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        INVARIANT TESTS
    //////////////////////////////////////////////////////////////*/

    function invariant_TVLNeverExceedsCap() public {
        uint256 currentTVL = vault_arb.totalAssets();
        uint256 tvlCap = yzEnforcedComposer_arb.tvlCap();
        
        if (tvlCap > 0) {
            assertLe(currentTVL, tvlCap, "TVL exceeds configured cap");
        }
    }

    function invariant_UserDepositsNeverExceedCaps() public {
        address[] memory users = _getFuzzUsers();
        
        for (uint256 i = 0; i < users.length; i++) {
            uint256 userDeposit = yzEnforcedComposer_arb.userDeposits(users[i]);
            uint256 userCap = yzEnforcedComposer_arb.userDepositCap(users[i]);
            
            if (userCap > 0) {
                assertLe(userDeposit, userCap, "User deposit exceeds individual cap");
            }
        }
    }

    function invariant_TotalUserDepositsEqualsTVL() public {
        address[] memory users = _getFuzzUsers();
        uint256 totalUserDeposits = 0;
        
        for (uint256 i = 0; i < users.length; i++) {
            totalUserDeposits += yzEnforcedComposer_arb.userDeposits(users[i]);
        }
        
        uint256 actualTVL = vault_arb.totalAssets();
        
        // Allow small rounding differences due to ERC4626 precision
        uint256 diff = actualTVL > totalUserDeposits ? 
                      actualTVL - totalUserDeposits : 
                      totalUserDeposits - actualTVL;
        
        assertLe(diff, 1 ether, "Total user deposits should equal TVL within rounding");
    }

    function invariant_ShareSupplyConsistentWithDeposits() public {
        uint256 totalShares = vault_arb.totalSupply();
        uint256 totalAssets = vault_arb.totalAssets();
        
        if (totalShares > 0) {
            assertGt(totalAssets, 0, "Shares exist but no assets");
        }
        
        if (totalShares > 0) {
            uint256 sharePrice = vault_arb.convertToAssets(1 ether);
            assertGe(sharePrice, 0.5 ether, "Share price too low");
            assertLe(sharePrice, 2 ether, "Share price too high");
        }
    }

    function invariant_PauseControlsWork() public {
        if (yzEnforcedComposer_arb.depositsPaused()) {
            // Deposits should be blocked
            uint256 depositAmount = 1 ether;
            _fundLocalFromHub(userA, depositAmount);
            vm.prank(userA);
            assetOFT_arb.approve(address(yzEnforcedComposer_arb), depositAmount);
            
            SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, depositAmount);
            
            vm.expectRevert(YZEnforcedComposer.YZ_DepositsPaused.selector);
            vm.prank(userA);
            yzEnforcedComposer_arb.depositAndSend(depositAmount, sendParam, userA);
        }
        
        if (yzEnforcedComposer_arb.redemptionsPaused()) {
            // Redemptions should be blocked
            uint256 redeemAmount = 1 ether;
            vm.prank(userA);
            vault_arb.approve(address(yzEnforcedComposer_arb), redeemAmount);
            
            SendParam memory redeemParam = _buildHopParam(address(0), userA, ARB_EID, redeemAmount);
            
            vm.expectRevert(YZEnforcedComposer.YZ_RedemptionsPaused.selector);
            vm.prank(userA);
            yzEnforcedComposer_arb.redeemAndSend(redeemAmount, redeemParam, userA);
        }
    }

    function invariant_AdminControlsRestricted() public {
        address nonAdmin = userA;
        
        // Test that non-admin cannot set TVL cap
        vm.expectRevert(YZEnforcedComposer.YZ_NotAdmin.selector);
        vm.prank(nonAdmin);
        yzEnforcedComposer_arb.setTVLCap(100 ether);
        
        // Test that non-admin cannot set user caps
        vm.expectRevert(YZEnforcedComposer.YZ_NotAdmin.selector);
        vm.prank(nonAdmin);
        yzEnforcedComposer_arb.setUserCap(nonAdmin, 100 ether);
        
        // Test that non-admin cannot pause
        vm.expectRevert(YZEnforcedComposer.YZ_NotAdmin.selector);
        vm.prank(nonAdmin);
        yzEnforcedComposer_arb.pauseDeposits();
        
        // Test that non-admin cannot set admin
        vm.expectRevert(YZEnforcedComposer.YZ_NotAdmin.selector);
        vm.prank(nonAdmin);
        yzEnforcedComposer_arb.setAdmin(nonAdmin);
    }

    function invariant_ViewFunctionsConsistency() public {
        address testUser = userA;
        uint256 userShares = vault_arb.balanceOf(testUser);
        uint256 userAssets = vault_arb.convertToAssets(userShares);
        
        // getUserShares should match vault balance
        assertEq(yzEnforcedComposer_arb.getUserShares(testUser), userShares);
        
        // getUserAssets should match converted assets
        assertEq(yzEnforcedComposer_arb.getUserAssets(testUser), userAssets);
        
        // getTotalValueLocked should match vault totalAssets
        assertEq(yzEnforcedComposer_arb.getTotalValueLocked(), vault_arb.totalAssets());
        
        // getUserDepositInfo should be consistent
        (uint256 deposit, uint256 cap, uint256 remaining) = yzEnforcedComposer_arb.getUserDepositInfo(testUser);
        assertEq(deposit, yzEnforcedComposer_arb.userDeposits(testUser));
        assertEq(cap, yzEnforcedComposer_arb.userDepositCap(testUser));
        
        if (cap > 0) {
            assertEq(remaining, cap - deposit);
        }
    }

    function invariant_CanDepositAccuracy() public {
        address testUser = userA;
        uint256 testAmount = 1 ether;
        
        (bool canDeposit, ) = yzEnforcedComposer_arb.canDeposit(testUser, testAmount);
        
        // Test the prediction by attempting the actual deposit
        _fundLocalFromHub(testUser, testAmount);
        vm.prank(testUser);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), testAmount);
        
        SendParam memory sendParam = _buildHopParam(address(0), testUser, ARB_EID, testAmount);
        
        if (canDeposit) {
            // Should succeed
            vm.prank(testUser);
            yzEnforcedComposer_arb.depositAndSend(testAmount, sendParam, testUser);
            _assertDepositSuccess(testUser, testAmount, testAmount);
        } else {
            // Should revert
            vm.expectRevert();
            vm.prank(testUser);
            yzEnforcedComposer_arb.depositAndSend(testAmount, sendParam, testUser);
            _assertNoStateChange();
        }
    }

    /*//////////////////////////////////////////////////////////////
                            FUZZ HELPERS
    //////////////////////////////////////////////////////////////*/

    function _fuzzDeposit() internal {
        address user = _getRandomUser();
        uint256 amount = _getRandomAmount();
        
        _setupUserCap(user, MAX_FUZZ_AMOUNT);
        _setupTVLCap(MAX_FUZZ_AMOUNT);
        
        _fundLocalFromHub(user, amount);
        vm.prank(user);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), amount);
        
        SendParam memory sendParam = _buildHopParam(address(0), user, ARB_EID, amount);
        
        vm.prank(user);
        yzEnforcedComposer_arb.depositAndSend(amount, sendParam, user);
        
        fuzzState.totalDeposits += amount;
    }

    function _fuzzRedeem() internal {
        address user = _getRandomUser();
        uint256 shares = vault_arb.balanceOf(user);
        
        if (shares > 0) {
            uint256 amount = _getRandomAmount();
            amount = amount > shares ? shares : amount;
            
            vm.prank(user);
            vault_arb.approve(address(yzEnforcedComposer_arb), amount);
            
            SendParam memory redeemParam = _buildHopParam(address(0), user, ARB_EID, amount);
            
            vm.prank(user);
            yzEnforcedComposer_arb.redeemAndSend(amount, redeemParam, user);
            
            fuzzState.totalRedemptions += amount;
        }
    }

    function _fuzzSetTVLCap() internal {
        uint256 cap = _getRandomAmount();
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(cap);
    }

    function _fuzzSetUserCap() internal {
        address user = _getRandomUser();
        uint256 cap = _getRandomAmount();
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(user, cap);
    }

    function _fuzzPauseDeposits() internal {
        vm.prank(admin);
        yzEnforcedComposer_arb.pauseDeposits();
        fuzzState.pausedDeposits = 1;
    }

    function _fuzzPauseRedemptions() internal {
        vm.prank(admin);
        yzEnforcedComposer_arb.pauseRedemptions();
        fuzzState.pausedRedemptions = 1;
    }

    function _fuzzSetWhitelist() internal {
        address user = _getRandomUser();
        bool status = _getRandomBool();
        
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelistEnabled(true);
        
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelist(user, status);
    }

    function _fuzzEmergencyWithdraw() internal {
        uint256 amount = _getRandomAmount();
        _fundLocalFromHub(address(yzEnforcedComposer_arb), amount);
        
        vm.prank(admin);
        yzEnforcedComposer_arb.emergencyWithdraw(amount, recipient);
    }

    function _fuzzAdminChanges() internal {
        address newAdmin = _getRandomUser();
        if (newAdmin != admin) {
            vm.prank(admin);
            yzEnforcedComposer_arb.setAdmin(newAdmin);
            admin = newAdmin;
        }
    }

    function _fuzzViewOperations() internal {
        address user = _getRandomUser();
        
        // Test view functions
        yzEnforcedComposer_arb.getTotalValueLocked();
        yzEnforcedComposer_arb.getUserShares(user);
        yzEnforcedComposer_arb.getUserAssets(user);
        yzEnforcedComposer_arb.getUserDepositInfo(user);
        yzEnforcedComposer_arb.canDeposit(user, _getRandomAmount());
    }

    function _fuzzUserDeposit(address user) internal {
        uint256 amount = _getRandomAmount();
        _setupUserCap(user, MAX_FUZZ_AMOUNT);
        _setupTVLCap(MAX_FUZZ_AMOUNT);
        
        _fundLocalFromHub(user, amount);
        vm.prank(user);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), amount);
        
        SendParam memory sendParam = _buildHopParam(address(0), user, ARB_EID, amount);
        
        vm.prank(user);
        yzEnforcedComposer_arb.depositAndSend(amount, sendParam, user);
    }

    function _fuzzUserRedeem(address user) internal {
        uint256 shares = vault_arb.balanceOf(user);
        
        if (shares > 0) {
            uint256 amount = _getRandomAmount();
            amount = amount > shares ? shares : amount;
            
            vm.prank(user);
            vault_arb.approve(address(yzEnforcedComposer_arb), amount);
            
            SendParam memory redeemParam = _buildHopParam(address(0), user, ARB_EID, amount);
            
            vm.prank(user);
            yzEnforcedComposer_arb.redeemAndSend(amount, redeemParam, user);
        }
    }

    function _fuzzUserCapChange(address user) internal {
        uint256 cap = _getRandomAmount();
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(user, cap);
    }

    function _fuzzUserWhitelistChange(address user) internal {
        bool status = _getRandomBool();
        
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelistEnabled(true);
        
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelist(user, status);
    }

    function _fuzzUserViewOperations(address user) internal {
        yzEnforcedComposer_arb.getUserShares(user);
        yzEnforcedComposer_arb.getUserAssets(user);
        yzEnforcedComposer_arb.getUserDepositInfo(user);
        yzEnforcedComposer_arb.canDeposit(user, _getRandomAmount());
    }

    function _fuzzBatchSetUserCaps() internal {
        address[] memory users = new address[](3);
        users[0] = _getRandomUser();
        users[1] = _getRandomUser();
        users[2] = _getRandomUser();
        
        uint256[] memory caps = new uint256[](3);
        caps[0] = _getRandomAmount();
        caps[1] = _getRandomAmount();
        caps[2] = _getRandomAmount();
        
        vm.prank(admin);
        yzEnforcedComposer_arb.batchSetUserCaps(users, caps);
    }

    function _fuzzCapBoundaryTesting() internal {
        uint256 cap = _getRandomAmount();
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(cap);
        
        // Test deposit at boundary
        address user = _getRandomUser();
        _setupUserCap(user, cap);
        
        _fundLocalFromHub(user, cap);
        vm.prank(user);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), cap);
        
        SendParam memory sendParam = _buildHopParam(address(0), user, ARB_EID, cap);
        
        vm.prank(user);
        yzEnforcedComposer_arb.depositAndSend(cap, sendParam, user);
    }

    function _fuzzCapRaceConditions() internal {
        uint256 cap = _getRandomAmount();
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(cap);
        
        // Multiple users trying to deposit near cap
        address user1 = _getRandomUser();
        address user2 = _getRandomUser();
        
        _setupUserCap(user1, cap);
        _setupUserCap(user2, cap);
        
        uint256 amount1 = cap / 2;
        uint256 amount2 = cap / 2 + 1;
        
        _fundLocalFromHub(user1, amount1);
        _fundLocalFromHub(user2, amount2);
        
        vm.prank(user1);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), amount1);
        vm.prank(user2);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), amount2);
        
        SendParam memory sendParam1 = _buildHopParam(address(0), user1, ARB_EID, amount1);
        SendParam memory sendParam2 = _buildHopParam(address(0), user2, ARB_EID, amount2);
        
        // First should succeed
        vm.prank(user1);
        yzEnforcedComposer_arb.depositAndSend(amount1, sendParam1, user1);
        
        // Second should fail if it would exceed cap
        vm.prank(user2);
        if (amount1 + amount2 > cap) {
            vm.expectRevert();
        }
        yzEnforcedComposer_arb.depositAndSend(amount2, sendParam2, user2);
    }

    function _fuzzCapConsistency() internal {
        uint256 cap = _getRandomAmount();
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(cap);
        
        // Verify cap is set correctly
        assertEq(yzEnforcedComposer_arb.tvlCap(), cap);
        
        // Test with various deposit amounts
        for (uint256 i = 0; i < 5; i++) {
            address user = _getRandomUser();
            uint256 amount = _getRandomAmount() % cap;
            
            _setupUserCap(user, cap);
            
            _fundLocalFromHub(user, amount);
            vm.prank(user);
            assetOFT_arb.approve(address(yzEnforcedComposer_arb), amount);
            
            SendParam memory sendParam = _buildHopParam(address(0), user, ARB_EID, amount);
            
            vm.prank(user);
            yzEnforcedComposer_arb.depositAndSend(amount, sendParam, user);
            
            // Verify TVL never exceeds cap
            assertLe(vault_arb.totalAssets(), cap);
        }
    }

    function _fuzzCapEdgeCases() internal {
        // Test zero cap
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(0);
        
        address user = _getRandomUser();
        uint256 amount = 1 ether;
        
        _fundLocalFromHub(user, amount);
        vm.prank(user);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), amount);
        
        SendParam memory sendParam = _buildHopParam(address(0), user, ARB_EID, amount);
        
        // Should succeed with zero cap (unlimited)
        vm.prank(user);
        yzEnforcedComposer_arb.depositAndSend(amount, sendParam, user);
        
        // Test very large cap
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(type(uint256).max);
        
        // Should work with large cap
        vm.prank(user);
        yzEnforcedComposer_arb.depositAndSend(amount, sendParam, user);
    }

    function _fuzzUnpauseDeposits() internal {
        vm.prank(admin);
        yzEnforcedComposer_arb.unpauseDeposits();
        fuzzState.pausedDeposits = 0;
    }

    function _fuzzUnpauseRedemptions() internal {
        vm.prank(admin);
        yzEnforcedComposer_arb.unpauseRedemptions();
        fuzzState.pausedRedemptions = 0;
    }

    function _fuzzPauseAll() internal {
        vm.prank(admin);
        yzEnforcedComposer_arb.pauseAll();
        fuzzState.pausedDeposits = 1;
        fuzzState.pausedRedemptions = 1;
    }

    function _fuzzUnpauseAll() internal {
        vm.prank(admin);
        yzEnforcedComposer_arb.unpauseAll();
        fuzzState.pausedDeposits = 0;
        fuzzState.pausedRedemptions = 0;
    }

    function _fuzzPauseRaceConditions() internal {
        // Toggle pause states rapidly
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(admin);
            yzEnforcedComposer_arb.pauseDeposits();
            
            vm.prank(admin);
            yzEnforcedComposer_arb.unpauseDeposits();
            
            vm.prank(admin);
            yzEnforcedComposer_arb.pauseRedemptions();
            
            vm.prank(admin);
            yzEnforcedComposer_arb.unpauseRedemptions();
        }
    }

    function _fuzzPauseEdgeCases() internal {
        // Test pause when already paused
        vm.prank(admin);
        yzEnforcedComposer_arb.pauseDeposits();
        
        vm.prank(admin);
        yzEnforcedComposer_arb.pauseDeposits(); // Should not revert
        
        // Test unpause when already unpaused
        vm.prank(admin);
        yzEnforcedComposer_arb.unpauseDeposits();
        
        vm.prank(admin);
        yzEnforcedComposer_arb.unpauseDeposits(); // Should not revert
    }

    function _fuzzSetWhitelistEnabled() internal {
        bool enabled = _getRandomBool();
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelistEnabled(enabled);
        fuzzState.whitelistEnabled = enabled ? 1 : 0;
    }

    function _fuzzBatchSetWhitelist(address[] memory users) internal {
        bool[] memory statuses = new bool[](users.length);
        for (uint256 i = 0; i < users.length; i++) {
            statuses[i] = _getRandomBool();
        }
        
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelistEnabled(true);
        
        vm.prank(admin);
        yzEnforcedComposer_arb.batchSetWhitelist(users, statuses);
    }

    function _fuzzWhitelistRaceConditions() internal {
        address user = _getRandomUser();
        bool status1 = _getRandomBool();
        bool status2 = _getRandomBool();
        
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelistEnabled(true);
        
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelist(user, status1);
        
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelist(user, status2);
        
        // Final status should be status2
        assertEq(yzEnforcedComposer_arb.whitelist(user), status2);
    }

    function _fuzzWhitelistEdgeCases() internal {
        // Test whitelist with zero address
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelistEnabled(true);
        
        vm.expectRevert(YZEnforcedComposer.YZ_ZeroAddress.selector);
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelist(address(0), true);
        
        // Test batch set with zero addresses
        address[] memory users = new address[](2);
        users[0] = _getRandomUser();
        users[1] = address(0);
        
        bool[] memory statuses = new bool[](2);
        statuses[0] = true;
        statuses[1] = false;
        
        vm.expectRevert("Length mismatch");
        vm.prank(admin);
        yzEnforcedComposer_arb.batchSetWhitelist(users, statuses);
    }

    function _fuzzWhitelistConsistency() internal {
        address user = _getRandomUser();
        bool status = _getRandomBool();
        
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelistEnabled(true);
        
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelist(user, status);
        
        assertEq(yzEnforcedComposer_arb.whitelist(user), status);
        
        // Test that whitelist status is consistent across operations
        if (status) {
            // Should be able to deposit
            uint256 amount = 1 ether;
            _setupUserCap(user, MAX_FUZZ_AMOUNT);
            _setupTVLCap(MAX_FUZZ_AMOUNT);
            
            _fundLocalFromHub(user, amount);
            vm.prank(user);
            assetOFT_arb.approve(address(yzEnforcedComposer_arb), amount);
            
            SendParam memory sendParam = _buildHopParam(address(0), user, ARB_EID, amount);
            
            vm.prank(user);
            yzEnforcedComposer_arb.depositAndSend(amount, sendParam, user);
        } else {
            // Should not be able to deposit
            uint256 amount = 1 ether;
            _fundLocalFromHub(user, amount);
            vm.prank(user);
            assetOFT_arb.approve(address(yzEnforcedComposer_arb), amount);
            
            SendParam memory sendParam = _buildHopParam(address(0), user, ARB_EID, amount);
            
            vm.expectRevert(YZEnforcedComposer.YZ_NotWhitelisted.selector);
            vm.prank(user);
            yzEnforcedComposer_arb.depositAndSend(amount, sendParam, user);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            CHECK HELPERS
    //////////////////////////////////////////////////////////////*/

    function _checkInvariants() internal {
        invariant_TVLNeverExceedsCap();
        invariant_UserDepositsNeverExceedCaps();
        invariant_TotalUserDepositsEqualsTVL();
        invariant_ShareSupplyConsistentWithDeposits();
        invariant_PauseControlsWork();
        invariant_AdminControlsRestricted();
        invariant_ViewFunctionsConsistency();
        invariant_CanDepositAccuracy();
    }

    function _checkMultiUserInvariants(address[] memory users) internal {
        for (uint256 i = 0; i < users.length; i++) {
            uint256 userDeposit = yzEnforcedComposer_arb.userDeposits(users[i]);
            uint256 userCap = yzEnforcedComposer_arb.userDepositCap(users[i]);
            
            if (userCap > 0) {
                assertLe(userDeposit, userCap, "User deposit exceeds individual cap");
            }
        }
        
        // Check total across all users
        uint256 totalUserDeposits = 0;
        for (uint256 i = 0; i < users.length; i++) {
            totalUserDeposits += yzEnforcedComposer_arb.userDeposits(users[i]);
        }
        
        uint256 actualTVL = vault_arb.totalAssets();
        uint256 diff = actualTVL > totalUserDeposits ? 
                      actualTVL - totalUserDeposits : 
                      totalUserDeposits - actualTVL;
        
        assertLe(diff, 1 ether, "Total user deposits should equal TVL within rounding");
    }

    function _checkCapInvariants() internal {
        uint256 currentTVL = vault_arb.totalAssets();
        uint256 tvlCap = yzEnforcedComposer_arb.tvlCap();
        
        if (tvlCap > 0) {
            assertLe(currentTVL, tvlCap, "TVL exceeds configured cap");
        }
    }

    function _checkPauseInvariants() internal {
        bool depositsPaused = yzEnforcedComposer_arb.depositsPaused();
        bool redemptionsPaused = yzEnforcedComposer_arb.redemptionsPaused();
        
        if (depositsPaused) {
            uint256 depositAmount = 1 ether;
            _fundLocalFromHub(userA, depositAmount);
            vm.prank(userA);
            assetOFT_arb.approve(address(yzEnforcedComposer_arb), depositAmount);
            
            SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, depositAmount);
            
            vm.expectRevert(YZEnforcedComposer.YZ_DepositsPaused.selector);
            vm.prank(userA);
            yzEnforcedComposer_arb.depositAndSend(depositAmount, sendParam, userA);
        }
        
        if (redemptionsPaused) {
            uint256 redeemAmount = 1 ether;
            vm.prank(userA);
            vault_arb.approve(address(yzEnforcedComposer_arb), redeemAmount);
            
            SendParam memory redeemParam = _buildHopParam(address(0), userA, ARB_EID, redeemAmount);
            
            vm.expectRevert(YZEnforcedComposer.YZ_RedemptionsPaused.selector);
            vm.prank(userA);
            yzEnforcedComposer_arb.redeemAndSend(redeemAmount, redeemParam, userA);
        }
    }

    function _checkWhitelistInvariants(address[] memory users) internal {
        if (yzEnforcedComposer_arb.whitelistEnabled()) {
            for (uint256 i = 0; i < users.length; i++) {
                bool isWhitelisted = yzEnforcedComposer_arb.whitelist(users[i]);
                
                if (isWhitelisted) {
                    // Should be able to deposit
                    uint256 amount = 1 ether;
                    _setupUserCap(users[i], MAX_FUZZ_AMOUNT);
                    _setupTVLCap(MAX_FUZZ_AMOUNT);
                    
                    _fundLocalFromHub(users[i], amount);
                    vm.prank(users[i]);
                    assetOFT_arb.approve(address(yzEnforcedComposer_arb), amount);
                    
                    SendParam memory sendParam = _buildHopParam(address(0), users[i], ARB_EID, amount);
                    
                    vm.prank(users[i]);
                    yzEnforcedComposer_arb.depositAndSend(amount, sendParam, users[i]);
                } else {
                    // Should not be able to deposit
                    uint256 amount = 1 ether;
                    _fundLocalFromHub(users[i], amount);
                    vm.prank(users[i]);
                    assetOFT_arb.approve(address(yzEnforcedComposer_arb), amount);
                    
                    SendParam memory sendParam = _buildHopParam(address(0), users[i], ARB_EID, amount);
                    
                    vm.expectRevert(YZEnforcedComposer.YZ_NotWhitelisted.selector);
                    vm.prank(users[i]);
                    yzEnforcedComposer_arb.depositAndSend(amount, sendParam, users[i]);
                }
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                            STATE HELPERS
    //////////////////////////////////////////////////////////////*/

    function _resetFuzzState() internal {
        fuzzState.totalDeposits = 0;
        fuzzState.totalRedemptions = 0;
        fuzzState.activeUsers = 0;
        fuzzState.pausedDeposits = 0;
        fuzzState.pausedRedemptions = 0;
        fuzzState.whitelistEnabled = 0;
    }

    function _getRandomUser() internal view returns (address) {
        uint256 random = uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty)));
        uint256 index = random % 10;
        return address(uint160(uint256(keccak256(abi.encodePacked("fuzzUser", index)))));
    }

    function _getRandomAmount() internal view returns (uint256) {
        uint256 random = uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty, block.coinbase)));
        return (random % MAX_FUZZ_AMOUNT) + MIN_FUZZ_AMOUNT;
    }

    function _getRandomBool() internal view returns (bool) {
        uint256 random = uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty)));
        return random % 2 == 0;
    }

    function _getFuzzUsers() internal pure returns (address[] memory) {
        address[] memory users = new address[](5);
        users[0] = address(uint160(uint256(keccak256(abi.encodePacked("fuzzUser", 0)))));
        users[1] = address(uint160(uint256(keccak256(abi.encodePacked("fuzzUser", 1)))));
        users[2] = address(uint160(uint256(keccak256(abi.encodePacked("fuzzUser", 2)))));
        users[3] = address(uint160(uint256(keccak256(abi.encodePacked("fuzzUser", 3)))));
        users[4] = address(uint160(uint256(keccak256(abi.encodePacked("fuzzUser", 4)))));
        return users;
    }

    function _setupDefaultCaps() internal {
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(MAX_FUZZ_AMOUNT);
    }

    function _setupUserCap(address user, uint256 cap) internal {
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(user, cap);
    }

    function _assertDepositSuccess(address user, uint256 depositAmount, uint256 expectedTVLIncrease) internal {
        assertEq(vault_arb.totalAssets(), expectedTVLIncrease);
        assertEq(yzEnforcedComposer_arb.userDeposits(user), depositAmount);
    }

    function _assertNoStateChange() internal {
        assertEq(vault_arb.totalAssets(), 0);
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), 0);
    }
}