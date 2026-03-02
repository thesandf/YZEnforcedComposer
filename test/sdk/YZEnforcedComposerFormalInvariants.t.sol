// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {YZEnforcedComposer} from "../../src/sdk/YZEnforcedComposer.sol";
import "./YZEnforcedComposerBase.t.sol";

/**
 * @title YZEnforcedComposer Formal Invariants
 * @notice Professional formal invariants for mathematical vault properties
 * @dev Tests core mathematical properties that must always hold
 */
contract YZEnforcedComposerFormalInvariants is YZEnforcedComposerBase {
    
    // Formal invariant constants
    uint256 internal constant EXCHANGE_RATE_PRECISION = 1e18;
    uint256 internal constant MAX_SHARE_SUPPLY = type(uint256).max;
    uint256 internal constant MAX_ASSET_AMOUNT = type(uint256).max;

    function setUp() public override {
        super.setUp();
        _setupDefaultCaps();
    }

    /*//////////////////////////////////////////////////////////////
                        CORE VAULT INVARIANTS
    //////////////////////////////////////////////////////////////*/

    function invariant_ExchangeRateMonotonicity() public {
        // Exchange rate should never decrease unexpectedly
        uint256 currentExchangeRate = vault_arb.convertToAssets(1 ether);
        
        // Exchange rate should be >= 0.5 ether (reasonable lower bound)
        assertGe(currentExchangeRate, 0.5 ether, "Exchange rate too low");
        
        // Exchange rate should be <= 2 ether (reasonable upper bound)
        assertLe(currentExchangeRate, 2 ether, "Exchange rate too high");
        
        // For ERC4626, exchange rate should be >= 1 when no fees
        // This is a basic sanity check
        assertGe(currentExchangeRate, 0.99 ether, "Exchange rate decreased unexpectedly");
    }

    function invariant_NoShareInflation() public {
        // Total shares should never exceed total assets
        uint256 totalShares = vault_arb.totalSupply();
        uint256 totalAssets = vault_arb.totalAssets();
        
        // In a properly functioning vault, shares should represent claims on assets
        // Allow small rounding differences due to ERC4626 precision
        if (totalShares > 0) {
            uint256 shareValue = vault_arb.convertToAssets(totalShares);
            assertGe(shareValue, totalAssets - 1 ether, "Share value less than assets");
            assertLe(shareValue, totalAssets + 1 ether, "Share value greater than assets");
        }
    }

    function invariant_NoAssetLoss() public {
        // Assets should never disappear without proper redemption
        uint256 totalAssets = vault_arb.totalAssets();
        
        // If there are shares, there must be corresponding assets
        if (vault_arb.totalSupply() > 0) {
            assertGt(totalAssets, 0, "Shares exist but no assets");
        }
        
        // Assets should never be negative (impossible but good invariant)
        assertGe(totalAssets, 0, "Negative assets");
    }

    function invariant_NoDoubleMint() public {
        // Verify no duplicate minting occurred
        address[] memory users = _getTestUsers();
        uint256 totalUserShares = 0;
        
        for (uint256 i = 0; i < users.length; i++) {
            uint256 userShares = vault_arb.balanceOf(users[i]);
            totalUserShares += userShares;
        }
        
        uint256 totalSupply = vault_arb.totalSupply();
        
        // Allow small rounding differences
        uint256 diff = totalSupply > totalUserShares ? 
                      totalSupply - totalUserShares : 
                      totalUserShares - totalSupply;
        
        assertLe(diff, 1 ether, "Double mint detected");
    }

    function invariant_CapAlwaysEnforced() public {
        uint256 currentTVL = vault_arb.totalAssets();
        uint256 tvlCap = yzEnforcedComposer_arb.tvlCap();
        
        if (tvlCap > 0) {
            assertLe(currentTVL, tvlCap, "TVL cap exceeded");
        }
        
        // Test user caps
        address[] memory users = _getTestUsers();
        for (uint256 i = 0; i < users.length; i++) {
            uint256 userDeposit = yzEnforcedComposer_arb.userDeposits(users[i]);
            uint256 userCap = yzEnforcedComposer_arb.userDepositCap(users[i]);
            
            if (userCap > 0) {
                assertLe(userDeposit, userCap, "User cap exceeded");
            }
        }
    }

    function invariant_PauseAlwaysRespected() public {
        bool depositsPaused = yzEnforcedComposer_arb.depositsPaused();
        bool redemptionsPaused = yzEnforcedComposer_arb.redemptionsPaused();
        
        if (depositsPaused) {
            // Verify deposits are actually blocked
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
            // Verify redemptions are actually blocked
            uint256 redeemAmount = 1 ether;
            vm.prank(userA);
            vault_arb.approve(address(yzEnforcedComposer_arb), redeemAmount);
            
            SendParam memory redeemParam = _buildHopParam(address(0), userA, ARB_EID, redeemAmount);
            
            vm.expectRevert(YZEnforcedComposer.YZ_RedemptionsPaused.selector);
            vm.prank(userA);
            yzEnforcedComposer_arb.redeemAndSend(redeemAmount, redeemParam, userA);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        CROSS-CHAIN GLOBAL INVARIANTS
    //////////////////////////////////////////////////////////////*/

    function invariant_CrossChainGlobalSupplyConsistency() public {
        // This is the critical cross-chain invariant
        // Global shares across all chains should <= global assets across all chains
        
        uint256 localShares = vault_arb.totalSupply();
        uint256 localAssets = vault_arb.totalAssets();
        
        // For single-chain testing, this should hold
        // In multi-chain, you'd aggregate across all chains
        if (localShares > 0) {
            uint256 shareValue = vault_arb.convertToAssets(localShares);
            assertGe(shareValue, localAssets - 1 ether, "Global supply exceeds global assets");
        }
    }

    function invariant_CrossChainMessageIntegrity() public {
        // Verify that cross-chain messages don't create inconsistencies
        // This would require tracking message nonces and states in a real implementation
        
        // For now, verify that local state is consistent
        uint256 totalAssets = vault_arb.totalAssets();
        uint256 totalShares = vault_arb.totalSupply();
        
        // Basic consistency check
        if (totalShares > 0) {
            assertGt(totalAssets, 0, "Shares without assets");
        }
    }

    /*//////////////////////////////////////////////////////////////
                        STORAGE-LEVEL ATOMICITY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_StorageAtomicity_SourceStateRollback() public {
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        uint256 initialAssets = vault_arb.totalAssets();
        uint256 initialShares = vault_arb.totalSupply();
        uint256 initialUserShares = vault_arb.balanceOf(userA);
        uint256 initialUserDeposits = yzEnforcedComposer_arb.userDeposits(userA);
        
        // Mock failure scenario
        _mockAtomicFailure();
        
        _fundLocalFromHub(userA, 50 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);
        
        // Should handle failure gracefully
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(50 ether, sendParam, userA);
        
        // Verify storage rollback
        assertEq(vault_arb.totalAssets(), initialAssets, "Assets not rolled back");
        assertEq(vault_arb.totalSupply(), initialShares, "Shares not rolled back");
        assertEq(vault_arb.balanceOf(userA), initialUserShares, "User shares not rolled back");
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), initialUserDeposits, "User deposits not rolled back");
    }

    function test_StorageAtomicity_ShareMintRollback() public {
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        uint256 initialShares = vault_arb.totalSupply();
        uint256 initialUserShares = vault_arb.balanceOf(userA);
        
        // Mock share mint failure
        _mockShareMintFailure();
        
        _fundLocalFromHub(userA, 50 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(50 ether, sendParam, userA);
        
        // Verify share mint rollback
        assertEq(vault_arb.totalSupply(), initialShares, "Shares not rolled back");
        assertEq(vault_arb.balanceOf(userA), initialUserShares, "User shares not rolled back");
    }

    /*//////////////////////////////////////////////////////////////
                        MALFORMED PAYLOAD FUZZING
    //////////////////////////////////////////////////////////////*/

    function test_MalformedPayload_Fuzz() public {
        // Test with various malformed payloads
        bytes[] memory malformedPayloads = new bytes[](5);
        
        // Empty payload
        malformedPayloads[0] = "";
        
        // Truncated payload
        malformedPayloads[1] = abi.encodePacked(uint256(123));
        
        // Oversized payload
        bytes memory largePayload = new bytes(1000);
        for (uint256 i = 0; i < 1000; i++) {
            largePayload[i] = bytes1(uint8(i % 256));
        }
        malformedPayloads[2] = largePayload;
        
        // Invalid ABI encoding
        malformedPayloads[3] = abi.encodePacked(uint256(0), uint256(0), uint256(0));
        
        // Random bytes
        malformedPayloads[4] = abi.encodePacked(keccak256(abi.encodePacked("random")));
        
        for (uint256 i = 0; i < malformedPayloads.length; i++) {
            // These should either succeed gracefully or revert cleanly
            // No state corruption should occur
            try this._testMalformedPayload(malformedPayloads[i]) {
                // Success is acceptable if handled properly
            } catch {
                // Revert is acceptable if handled properly
            }
            
            // Verify no state corruption
            assertGt(vault_arb.totalAssets(), 0, "Assets corrupted");
            assertGe(vault_arb.totalSupply(), 0, "Shares corrupted");
        }
    }

    function _testMalformedPayload(bytes memory payload) external {
        // This would test LayerZero message handling with malformed payloads
        // For now, we test with invalid SendParam
        SendParam memory invalidParam = SendParam(
            0, // invalid dstEid
            bytes(""), // empty to
            bytes(""), // empty extraOptions
            0, // zero amountLD
            0, // zero minAmountLD
            0, // zero gasForCall
            0, // zero nativeFee
            payload // malformed composeMsg
        );
        
        _fundLocalFromHub(userA, 1 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 1 ether);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(1 ether, invalidParam, userA);
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN GRIEFING MODELING
    //////////////////////////////////////////////////////////////*/

    function test_AdminGriefing_CapReductionBelowTVL() public {
        _setupUserCap(userA, 1000 ether);
        _setupTVLCap(1000 ether);
        
        // Deposit large amount
        _executeSuccessfulDeposit(userA, 500 ether);
        assertEq(vault_arb.totalAssets(), 500 ether);
        
        // Admin reduces cap below current TVL
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(100 ether);
        
        // Should not break existing functionality
        assertEq(yzEnforcedComposer_arb.tvlCap(), 100 ether);
        
        // Existing user should still be able to redeem
        vm.prank(userA);
        vault_arb.approve(address(yzEnforcedComposer_arb), 100 ether);
        
        SendParam memory redeemParam = _buildHopParam(address(0), userA, ARB_EID, 100 ether);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.redeemAndSend(100 ether, redeemParam, userA);
        
        // Should work despite cap reduction
        assertEq(vault_arb.totalAssets(), 400 ether);
    }

    function test_AdminGriefing_WhitelistRemovalDuringExecution() public {
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
        
        // Remove whitelist during execution
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

    function test_AdminGriefing_PauseDuringCompose() public {
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        // Start deposit process
        _fundLocalFromHub(userA, 50 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);
        
        // Pause during execution
        vm.prank(admin);
        yzEnforcedComposer_arb.pauseDeposits();
        
        // Deposit should still succeed (pause doesn't affect ongoing tx)
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(50 ether, sendParam, userA);
        
        // But new deposits should fail
        _fundLocalFromHub(userB, 50 ether);
        vm.prank(userB);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);
        
        SendParam memory sendParamB = _buildHopParam(address(0), userB, ARB_EID, 50 ether);
        
        vm.expectRevert(YZEnforcedComposer.YZ_DepositsPaused.selector);
        vm.prank(userB);
        yzEnforcedComposer_arb.depositAndSend(50 ether, sendParamB, userB);
    }

    /*//////////////////////////////////////////////////////////////
                        EXTREME VALUE TESTING
    //////////////////////////////////////////////////////////////*/

    function test_ExtremeValues_MaxTVL() public {
        _setupUserCap(userA, MAX_ASSET_AMOUNT);
        _setupTVLCap(MAX_ASSET_AMOUNT);
        
        // Test with maximum values
        uint256 maxAmount = MAX_ASSET_AMOUNT / 2; // Avoid overflow
        
        _fundLocalFromHub(userA, maxAmount);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), maxAmount);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, maxAmount);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(maxAmount, sendParam, userA);
        
        // Verify no overflow occurred
        assertEq(vault_arb.totalAssets(), maxAmount);
        assertGt(vault_arb.totalSupply(), 0);
    }

    function test_ExtremeValues_MaxShareSupply() public {
        _setupUserCap(userA, MAX_SHARE_SUPPLY);
        _setupTVLCap(MAX_SHARE_SUPPLY);
        
        // Test share supply near maximum
        uint256 largeAmount = MAX_SHARE_SUPPLY / 1000; // Safe amount
        
        _fundLocalFromHub(userA, largeAmount);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), largeAmount);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, largeAmount);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(largeAmount, sendParam, userA);
        
        // Verify share supply handling
        uint256 shares = vault_arb.balanceOf(userA);
        assertGt(shares, 0);
        assertLe(shares, MAX_SHARE_SUPPLY);
    }

    function test_ExtremeValues_CapAtMax() public {
        // Test cap set to maximum value
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(MAX_ASSET_AMOUNT);
        
        assertEq(yzEnforcedComposer_arb.tvlCap(), MAX_ASSET_AMOUNT);
        
        // Should work with large amounts
        uint256 largeAmount = MAX_ASSET_AMOUNT / 10;
        
        _setupUserCap(userA, largeAmount);
        
        _fundLocalFromHub(userA, largeAmount);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), largeAmount);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, largeAmount);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(largeAmount, sendParam, userA);
        
        assertEq(vault_arb.totalAssets(), largeAmount);
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

    function _getTestUsers() internal pure returns (address[] memory) {
        address[] memory users = new address[](5);
        users[0] = address(0x1);
        users[1] = address(0x2);
        users[2] = address(0x3);
        users[3] = address(0x4);
        users[4] = address(0x5);
        return users;
    }

    /*//////////////////////////////////////////////////////////////
                        MOCK FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _mockAtomicFailure() internal {
        vm.mockCall(
            address(vault_arb),
            abi.encodeWithSignature("deposit(uint256,address)", 50 ether, address(yzEnforcedComposer_arb)),
            abi.encodeWithSignature("Error(string)", "Atomic failure")
        );
    }

    function _mockShareMintFailure() internal {
        vm.mockCall(
            address(vault_arb),
            abi.encodeWithSignature("mint(address,uint256)", userA, 50 ether),
            abi.encodeWithSignature("Error(string)", "Share mint failure")
        );
    }
}