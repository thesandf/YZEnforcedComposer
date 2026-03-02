// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {YZEnforcedComposer} from "../../src/sdk/YZEnforcedComposer.sol";
import "./YZEnforcedComposerBase.t.sol";

/**
 * @title YZEnforcedComposer Unit Tests
 * @notice Professional audit-grade unit tests for YZEnforcedComposer
 * @dev Tests core functionality, risk controls, and edge cases
 */
contract YZEnforcedComposerUnitTest is YZEnforcedComposerBase {
    
    // Test constants
    uint256 internal constant MAX_TEST_AMOUNT = 1000 ether;
    uint256 internal constant MIN_TEST_AMOUNT = 1 ether;
    
    // Test addresses for edge cases
    address internal constant ZERO_ADDRESS = address(0);
    address internal constant NON_CONTRACT_ADDRESS = address(0x1234567890123456789012345678901234567890);

    function setUp() public override {
        super.setUp();
        _setupDefaultCaps();
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Deposit_SucceedsWhenWithinAllLimits() public {
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        uint256 depositAmount = 50 ether;
        _executeSuccessfulDeposit(userA, depositAmount);
        
        _assertDepositSuccess(userA, depositAmount, depositAmount);
    }

    function test_Deposit_RevertsWhenTVLCapExceeded() public {
        uint256 tvlCap = 50 ether;
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(tvlCap);
        
        uint256 depositAmount = 60 ether;
        _fundLocalFromHub(userA, depositAmount);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), depositAmount);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, depositAmount);
        
        vm.expectRevert(
            abi.encodeWithSelector(
                YZEnforcedComposer.YZ_TVLCapExceeded.selector,
                0,
                depositAmount,
                tvlCap
            )
        );
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(depositAmount, sendParam, userA);
        
        _assertNoStateChange();
    }

    function test_Deposit_RevertsWhenUserCapExceeded() public {
        uint256 userCap = 40 ether;
        _setupUserCap(userA, userCap);
        
        uint256 depositAmount = 50 ether;
        _fundLocalFromHub(userA, depositAmount);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), depositAmount);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, depositAmount);
        
        vm.expectRevert(
            abi.encodeWithSelector(
                YZEnforcedComposer.YZ_UserCapExceeded.selector,
                userA,
                0,
                depositAmount,
                userCap
            )
        );
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(depositAmount, sendParam, userA);
        
        _assertNoStateChange();
    }

    function test_Deposit_RevertsWhenDepositsPaused() public {
        vm.prank(admin);
        yzEnforcedComposer_arb.pauseDeposits();
        
        uint256 depositAmount = 50 ether;
        _fundLocalFromHub(userA, depositAmount);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), depositAmount);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, depositAmount);
        
        vm.expectRevert(YZEnforcedComposer.YZ_DepositsPaused.selector);
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(depositAmount, sendParam, userA);
        
        _assertNoStateChange();
    }

    function test_Deposit_RevertsWhenNotWhitelisted() public {
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelistEnabled(true);
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelist(userA, false);
        
        uint256 depositAmount = 50 ether;
        _fundLocalFromHub(userA, depositAmount);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), depositAmount);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, depositAmount);
        
        vm.expectRevert(YZEnforcedComposer.YZ_NotWhitelisted.selector);
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(depositAmount, sendParam, userA);
        
        _assertNoStateChange();
    }

    function test_Deposit_ExactCapBoundary_Succeeds() public {
        uint256 cap = 100 ether;
        _setupUserCap(userA, cap);
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(cap);
        
        _executeSuccessfulDeposit(userA, cap);
        _assertDepositSuccess(userA, cap, cap);
    }

    function test_Deposit_CapExceededByOneWei_Reverts() public {
        uint256 cap = 100 ether;
        _setupUserCap(userA, cap);
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(cap);
        
        uint256 depositAmount = cap + 1;
        _fundLocalFromHub(userA, depositAmount);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), depositAmount);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, depositAmount);
        
        vm.expectRevert();
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(depositAmount, sendParam, userA);
        
        _assertNoStateChange();
    }

    function test_Deposit_ZeroAmount_Reverts() public {
        uint256 depositAmount = 0;
        _fundLocalFromHub(userA, depositAmount);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), depositAmount);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, depositAmount);
        
        vm.expectRevert();
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(depositAmount, sendParam, userA);
        
        _assertNoStateChange();
    }

    /*//////////////////////////////////////////////////////////////
                            REDEEM TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Redeem_SucceedsWhenWithinLimits() public {
        uint256 initialDeposit = 100 ether;
        _executeSuccessfulDeposit(userA, initialDeposit);
        
        uint256 redeemAmount = 50 ether;
        _executeSuccessfulRedeem(userA, redeemAmount);
        
        _assertRedeemSuccess(userA, initialDeposit, redeemAmount);
    }

    function test_Redeem_RevertsWhenRedemptionsPaused() public {
        uint256 initialDeposit = 100 ether;
        _executeSuccessfulDeposit(userA, initialDeposit);
        
        vm.prank(admin);
        yzEnforcedComposer_arb.pauseRedemptions();
        
        uint256 redeemAmount = 50 ether;
        vm.prank(userA);
        vault_arb.approve(address(yzEnforcedComposer_arb), redeemAmount);
        
        SendParam memory redeemParam = _buildHopParam(address(0), userA, ARB_EID, redeemAmount);
        
        vm.expectRevert(YZEnforcedComposer.YZ_RedemptionsPaused.selector);
        vm.prank(userA);
        yzEnforcedComposer_arb.redeemAndSend(redeemAmount, redeemParam, userA);
        
        _assertRedeemNoStateChange(userA, initialDeposit);
    }

    function test_Redeem_RevertsWhenInsufficientShares() public {
        uint256 redeemAmount = 100 ether;
        vm.prank(userA);
        vault_arb.approve(address(yzEnforcedComposer_arb), redeemAmount);
        
        SendParam memory redeemParam = _buildHopParam(address(0), userA, ARB_EID, redeemAmount);
        
        vm.expectRevert();
        vm.prank(userA);
        yzEnforcedComposer_arb.redeemAndSend(redeemAmount, redeemParam, userA);
        
        _assertNoStateChange();
    }

    function test_Redeem_ExactSharesBoundary_Succeeds() public {
        uint256 initialDeposit = 100 ether;
        _executeSuccessfulDeposit(userA, initialDeposit);
        
        uint256 redeemAmount = 100 ether;
        _executeSuccessfulRedeem(userA, redeemAmount);
        
        _assertRedeemSuccess(userA, initialDeposit, redeemAmount);
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), 0);
    }

    /*//////////////////////////////////////////////////////////////
                            CAP MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetTVLCap_UpdatesCapAndEmitsEvent() public {
        uint256 newCap = 100 ether;
        
        vm.expectEmit(true, true, true, true);
        emit YZEnforcedComposer.TVLCapUpdated(0, newCap);
        
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(newCap);
        
        assertEq(yzEnforcedComposer_arb.tvlCap(), newCap);
    }

    function test_SetUserCap_UpdatesCapAndEmitsEvent() public {
        uint256 newCap = 50 ether;
        
        vm.expectEmit(true, true, true, true);
        emit YZEnforcedComposer.UserCapUpdated(userA, 0, newCap);
        
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(userA, newCap);
        
        assertEq(yzEnforcedComposer_arb.userDepositCap(userA), newCap);
    }

    function test_SetUserCap_RevertsOnZeroAddress() public {
        vm.expectRevert(YZEnforcedComposer.YZ_ZeroAddress.selector);
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(ZERO_ADDRESS, 50 ether);
    }

    function test_BatchSetUserCaps_UpdatesMultipleCaps() public {
        address[] memory users = new address[](2);
        users[0] = userA;
        users[1] = userB;
        
        uint256[] memory caps = new uint256[](2);
        caps[0] = 50 ether;
        caps[1] = 100 ether;
        
        vm.prank(admin);
        yzEnforcedComposer_arb.batchSetUserCaps(users, caps);
        
        assertEq(yzEnforcedComposer_arb.userDepositCap(userA), 50 ether);
        assertEq(yzEnforcedComposer_arb.userDepositCap(userB), 100 ether);
    }

    function test_BatchSetUserCaps_RevertsOnLengthMismatch() public {
        address[] memory users = new address[](2);
        users[0] = userA;
        users[1] = userB;
        
        uint256[] memory caps = new uint256[](1);
        caps[0] = 50 ether;
        
        vm.expectRevert("Length mismatch");
        vm.prank(admin);
        yzEnforcedComposer_arb.batchSetUserCaps(users, caps);
    }

    /*//////////////////////////////////////////////////////////////
                            PAUSE CONTROLS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_PauseDeposits_UpdatesStateAndEmitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit YZEnforcedComposer.DepositsPaused(admin);
        
        vm.prank(admin);
        yzEnforcedComposer_arb.pauseDeposits();
        
        assertTrue(yzEnforcedComposer_arb.depositsPaused());
    }

    function test_UnpauseDeposits_UpdatesStateAndEmitsEvent() public {
        vm.prank(admin);
        yzEnforcedComposer_arb.pauseDeposits();
        
        vm.expectEmit(true, true, true, true);
        emit YZEnforcedComposer.DepositsUnpaused(admin);
        
        vm.prank(admin);
        yzEnforcedComposer_arb.unpauseDeposits();
        
        assertFalse(yzEnforcedComposer_arb.depositsPaused());
    }

    function test_PauseRedemptions_UpdatesStateAndEmitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit YZEnforcedComposer.RedemptionsPaused(admin);
        
        vm.prank(admin);
        yzEnforcedComposer_arb.pauseRedemptions();
        
        assertTrue(yzEnforcedComposer_arb.redemptionsPaused());
    }

    function test_UnpauseRedemptions_UpdatesStateAndEmitsEvent() public {
        vm.prank(admin);
        yzEnforcedComposer_arb.pauseRedemptions();
        
        vm.expectEmit(true, true, true, true);
        emit YZEnforcedComposer.RedemptionsUnpaused(admin);
        
        vm.prank(admin);
        yzEnforcedComposer_arb.unpauseRedemptions();
        
        assertFalse(yzEnforcedComposer_arb.redemptionsPaused());
    }

    function test_PauseAll_UpdatesBothStates() public {
        vm.prank(admin);
        yzEnforcedComposer_arb.pauseAll();
        
        assertTrue(yzEnforcedComposer_arb.depositsPaused());
        assertTrue(yzEnforcedComposer_arb.redemptionsPaused());
    }

    function test_UnpauseAll_UpdatesBothStates() public {
        vm.prank(admin);
        yzEnforcedComposer_arb.pauseAll();
        
        vm.prank(admin);
        yzEnforcedComposer_arb.unpauseAll();
        
        assertFalse(yzEnforcedComposer_arb.depositsPaused());
        assertFalse(yzEnforcedComposer_arb.redemptionsPaused());
    }

    /*//////////////////////////////////////////////////////////////
                            WHITELIST TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetWhitelistEnabled_UpdatesStateAndEmitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit YZEnforcedComposer.WhitelistEnabled(true);
        
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelistEnabled(true);
        
        assertTrue(yzEnforcedComposer_arb.whitelistEnabled());
    }

    function test_SetWhitelist_UpdatesStatusAndEmitsEvent() public {
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelistEnabled(true);
        
        vm.expectEmit(true, true, true, true);
        emit YZEnforcedComposer.WhitelistUpdated(userA, true);
        
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelist(userA, true);
        
        assertTrue(yzEnforcedComposer_arb.whitelist(userA));
    }

    function test_BatchSetWhitelist_UpdatesMultipleStatuses() public {
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelistEnabled(true);
        
        address[] memory users = new address[](2);
        users[0] = userA;
        users[1] = userB;
        
        bool[] memory statuses = new bool[](2);
        statuses[0] = true;
        statuses[1] = false;
        
        vm.prank(admin);
        yzEnforcedComposer_arb.batchSetWhitelist(users, statuses);
        
        assertTrue(yzEnforcedComposer_arb.whitelist(userA));
        assertFalse(yzEnforcedComposer_arb.whitelist(userB));
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN CONTROLS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetAdmin_UpdatesAdminAndEmitsEvent() public {
        address newAdmin = NON_CONTRACT_ADDRESS;
        
        vm.expectEmit(true, true, true, true);
        emit YZEnforcedComposer.AdminUpdated(admin, newAdmin);
        
        vm.prank(admin);
        yzEnforcedComposer_arb.setAdmin(newAdmin);
        
        assertEq(yzEnforcedComposer_arb.admin(), newAdmin);
    }

    function test_SetAdmin_RevertsOnZeroAddress() public {
        vm.expectRevert(YZEnforcedComposer.YZ_ZeroAddress.selector);
        vm.prank(admin);
        yzEnforcedComposer_arb.setAdmin(ZERO_ADDRESS);
    }

    function test_SetAdmin_RevertsOnNonAdmin() public {
        vm.expectRevert(YZEnforcedComposer.YZ_NotAdmin.selector);
        vm.prank(userA);
        yzEnforcedComposer_arb.setAdmin(userB);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetTotalValueLocked_ReturnsCorrectValue() public {
        uint256 depositAmount = 100 ether;
        _executeSuccessfulDeposit(userA, depositAmount);
        
        uint256 expectedTVL = vault_arb.totalAssets();
        uint256 actualTVL = yzEnforcedComposer_arb.getTotalValueLocked();
        
        assertEq(actualTVL, expectedTVL);
    }

    function test_GetUserShares_ReturnsCorrectValue() public {
        uint256 depositAmount = 100 ether;
        _executeSuccessfulDeposit(userA, depositAmount);
        
        uint256 expectedShares = vault_arb.balanceOf(userA);
        uint256 actualShares = yzEnforcedComposer_arb.getUserShares(userA);
        
        assertEq(actualShares, expectedShares);
    }

    function test_GetUserAssets_ReturnsCorrectValue() public {
        uint256 depositAmount = 100 ether;
        _executeSuccessfulDeposit(userA, depositAmount);
        
        uint256 expectedAssets = vault_arb.convertToAssets(vault_arb.balanceOf(userA));
        uint256 actualAssets = yzEnforcedComposer_arb.getUserAssets(userA);
        
        assertEq(actualAssets, expectedAssets);
    }

    function test_GetUserDepositInfo_ReturnsCorrectValues() public {
        uint256 userCap = 100 ether;
        _setupUserCap(userA, userCap);
        
        uint256 depositAmount = 50 ether;
        _executeSuccessfulDeposit(userA, depositAmount);
        
        (uint256 deposit, uint256 cap, uint256 remaining) = yzEnforcedComposer_arb.getUserDepositInfo(userA);
        
        assertEq(deposit, depositAmount);
        assertEq(cap, userCap);
        assertEq(remaining, userCap - depositAmount);
    }

    function test_CanDeposit_ReturnsCorrectBooleans() public {
        uint256 userCap = 100 ether;
        _setupUserCap(userA, userCap);
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(200 ether);
        
        // Test within limits
        (bool allowed, ) = yzEnforcedComposer_arb.canDeposit(userA, 50 ether);
        assertTrue(allowed);
        
        // Test user cap exceeded
        (allowed, ) = yzEnforcedComposer_arb.canDeposit(userA, 150 ether);
        assertFalse(allowed);
        
        // Test TVL cap exceeded
        _executeSuccessfulDeposit(userA, 100 ether);
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(150 ether);
        _executeSuccessfulDeposit(userB, 60 ether);
        
        (allowed, ) = yzEnforcedComposer_arb.canDeposit(userA, 10 ether);
        assertFalse(allowed);
    }

    /*//////////////////////////////////////////////////////////////
                            EMERGENCY FUNCTIONS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_EmergencyWithdraw_Assets_TransfersCorrectly() public {
        uint256 withdrawAmount = 50 ether;
        _fundLocalFromHub(address(yzEnforcedComposer_arb), withdrawAmount);
        
        vm.prank(admin);
        yzEnforcedComposer_arb.emergencyWithdraw(withdrawAmount, recipient);
        
        assertEq(assetOFT_arb.balanceOf(recipient), withdrawAmount);
    }

    function test_EmergencyWithdraw_Assets_RevertsOnZeroAddress() public {
        uint256 withdrawAmount = 50 ether;
        _fundLocalFromHub(address(yzEnforcedComposer_arb), withdrawAmount);
        
        vm.expectRevert(YZEnforcedComposer.YZ_ZeroAddress.selector);
        vm.prank(admin);
        yzEnforcedComposer_arb.emergencyWithdraw(withdrawAmount, ZERO_ADDRESS);
    }

    function test_EmergencyWithdraw_Assets_RevertsOnZeroAmount() public {
        vm.expectRevert("Zero amount");
        vm.prank(admin);
        yzEnforcedComposer_arb.emergencyWithdraw(0, recipient);
    }

    function test_EmergencyWithdraw_Assets_RevertsOnInsufficientBalance() public {
        uint256 withdrawAmount = 100 ether;
        
        vm.expectRevert("Insufficient balance");
        vm.prank(admin);
        yzEnforcedComposer_arb.emergencyWithdraw(withdrawAmount, recipient);
    }

    function test_EmergencyWithdraw_Shares_TransfersCorrectly() public {
        uint256 depositAmount = 100 ether;
        _executeSuccessfulDeposit(userA, depositAmount);
        
        uint256 withdrawAmount = 50 ether;
        vm.prank(address(yzEnforcedComposer_arb));
        vault_arb.approve(address(yzEnforcedComposer_arb), withdrawAmount);
        
        vm.prank(admin);
        yzEnforcedComposer_arb.emergencyWithdrawShares(withdrawAmount, recipient);
        
        assertEq(vault_arb.balanceOf(recipient), withdrawAmount);
    }

    function test_EmergencyWithdraw_Native_TransfersCorrectly() public {
        uint256 withdrawAmount = 1 ether;
        vm.deal(address(yzEnforcedComposer_arb), withdrawAmount);
        
        vm.prank(admin);
        yzEnforcedComposer_arb.emergencyWithdrawNative(withdrawAmount, payable(recipient));
        
        assertEq(recipient.balance, withdrawAmount);
    }

    function test_EmergencyWithdraw_RevertsOnNonAdmin() public {
        uint256 withdrawAmount = 50 ether;
        _fundLocalFromHub(address(yzEnforcedComposer_arb), withdrawAmount);
        
        vm.expectRevert(YZEnforcedComposer.YZ_NotAdmin.selector);
        vm.prank(userA);
        yzEnforcedComposer_arb.emergencyWithdraw(withdrawAmount, recipient);
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

    function _executeSuccessfulRedeem(address user, uint256 amount) internal {
        vm.prank(user);
        vault_arb.approve(address(yzEnforcedComposer_arb), amount);
        
        SendParam memory redeemParam = _buildHopParam(address(0), user, ARB_EID, amount);
        
        vm.prank(user);
        yzEnforcedComposer_arb.redeemAndSend(amount, redeemParam, user);
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
}