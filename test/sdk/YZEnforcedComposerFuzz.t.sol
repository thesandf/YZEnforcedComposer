// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {YZEnforcedComposer} from "../../src/sdk/YZEnforcedComposer.sol";
import "./YZEnforcedComposerBase.t.sol";

/**
 * @title YZEnforcedComposer Fuzz Tests
 * @notice Professional fuzz tests for YZEnforcedComposer
 * @dev Tests edge cases, boundary conditions, and property-based invariants
 */
contract YZEnforcedComposerFuzzTest is YZEnforcedComposerBase {
    
    // Fuzz test constants
    uint256 internal constant MAX_FUZZ_AMOUNT = 1000 ether;
    uint256 internal constant MIN_FUZZ_AMOUNT = 1 ether;
    uint256 internal constant MAX_CAP = 500 ether;
    uint256 internal constant MIN_CAP = 1 ether;

    function setUp() public override {
        super.setUp();
        _setupDefaultCaps();
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Deposit_AmountWithinBounds(uint256 _amount) public {
        _amount = bound(_amount, MIN_FUZZ_AMOUNT, MAX_FUZZ_AMOUNT);
        
        _setupUserCap(userA, MAX_FUZZ_AMOUNT);
        _setupTVLCap(MAX_FUZZ_AMOUNT);
        
        _executeSuccessfulDeposit(userA, _amount);
        _assertDepositSuccess(userA, _amount, _amount);
    }

    function testFuzz_Deposit_RevertsWhenTVLCapExceeded(uint256 _tvlCap, uint256 _depositAmount) public {
        _tvlCap = bound(_tvlCap, MIN_CAP, MAX_CAP);
        _depositAmount = bound(_depositAmount, _tvlCap + 1, MAX_FUZZ_AMOUNT);
        
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(_tvlCap);
        
        _fundLocalFromHub(userA, _depositAmount);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), _depositAmount);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, _depositAmount);
        
        vm.expectRevert(
            abi.encodeWithSelector(
                YZEnforcedComposer.YZ_TVLCapExceeded.selector,
                0,
                _depositAmount,
                _tvlCap
            )
        );
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(_depositAmount, sendParam, userA);
        
        _assertNoStateChange();
    }

    function testFuzz_Deposit_RevertsWhenUserCapExceeded(uint256 _userCap, uint256 _depositAmount) public {
        _userCap = bound(_userCap, MIN_CAP, MAX_CAP);
        _depositAmount = bound(_depositAmount, _userCap + 1, MAX_FUZZ_AMOUNT);
        
        _setupUserCap(userA, _userCap);
        
        _fundLocalFromHub(userA, _depositAmount);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), _depositAmount);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, _depositAmount);
        
        vm.expectRevert(
            abi.encodeWithSelector(
                YZEnforcedComposer.YZ_UserCapExceeded.selector,
                userA,
                0,
                _depositAmount,
                _userCap
            )
        );
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(_depositAmount, sendParam, userA);
        
        _assertNoStateChange();
    }

    function testFuzz_Deposit_MultipleUsersWithinCaps(
        uint256 _userACap,
        uint256 _userADeposit,
        uint256 _userBCap,
        uint256 _userBDeposit,
        uint256 _tvlCap
    ) public {
        _userACap = bound(_userACap, MIN_CAP, MAX_CAP);
        _userADeposit = bound(_userADeposit, MIN_FUZZ_AMOUNT, _userACap);
        _userBCap = bound(_userBCap, MIN_CAP, MAX_CAP);
        _userBDeposit = bound(_userBDeposit, MIN_FUZZ_AMOUNT, _userBCap);
        _tvlCap = bound(_tvlCap, _userADeposit + _userBDeposit, MAX_FUZZ_AMOUNT);
        
        _setupUserCap(userA, _userACap);
        _setupUserCap(userB, _userBCap);
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(_tvlCap);
        
        // User A deposits
        _executeSuccessfulDeposit(userA, _userADeposit);
        _assertDepositSuccess(userA, _userADeposit, _userADeposit);
        
        // User B deposits
        _executeSuccessfulDeposit(userB, _userBDeposit);
        _assertDepositSuccess(userB, _userBDeposit, _userADeposit + _userBDeposit);
        
        // Verify caps not exceeded
        assertLe(yzEnforcedComposer_arb.userDeposits(userA), _userACap);
        assertLe(yzEnforcedComposer_arb.userDeposits(userB), _userBCap);
        assertLe(vault_arb.totalAssets(), _tvlCap);
    }

    function testFuzz_Deposit_ExactCapBoundary(uint256 _cap) public {
        _cap = bound(_cap, MIN_CAP, MAX_CAP);
        
        _setupUserCap(userA, _cap);
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(_cap);
        
        _executeSuccessfulDeposit(userA, _cap);
        _assertDepositSuccess(userA, _cap, _cap);
        
        // Verify exactly at cap
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), _cap);
        assertEq(vault_arb.totalAssets(), _cap);
    }

    function testFuzz_Deposit_CapExceededByOneWei(uint256 _cap) public {
        _cap = bound(_cap, MIN_CAP, MAX_CAP);
        
        _setupUserCap(userA, _cap);
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(_cap);
        
        uint256 depositAmount = _cap + 1;
        _fundLocalFromHub(userA, depositAmount);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), depositAmount);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, depositAmount);
        
        vm.expectRevert();
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(depositAmount, sendParam, userA);
        
        _assertNoStateChange();
    }

    function testFuzz_Deposit_ZeroAmountAlwaysReverts(uint256 _unused) public {
        // This test ensures zero amount always reverts regardless of other parameters
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
                            REDEEM FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Redeem_AmountWithinShares(uint256 _initialDeposit, uint256 _redeemAmount) public {
        _initialDeposit = bound(_initialDeposit, MIN_FUZZ_AMOUNT, MAX_FUZZ_AMOUNT);
        _redeemAmount = bound(_redeemAmount, MIN_FUZZ_AMOUNT, _initialDeposit);
        
        _executeSuccessfulDeposit(userA, _initialDeposit);
        _executeSuccessfulRedeem(userA, _redeemAmount);
        
        _assertRedeemSuccess(userA, _initialDeposit, _redeemAmount);
    }

    function testFuzz_Redeem_ExactSharesBoundary(uint256 _initialDeposit) public {
        _initialDeposit = bound(_initialDeposit, MIN_FUZZ_AMOUNT, MAX_FUZZ_AMOUNT);
        
        _executeSuccessfulDeposit(userA, _initialDeposit);
        _executeSuccessfulRedeem(userA, _initialDeposit);
        
        _assertRedeemSuccess(userA, _initialDeposit, _initialDeposit);
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), 0);
    }

    function testFuzz_Redeem_RevertsWhenInsufficientShares(uint256 _redeemAmount) public {
        _redeemAmount = bound(_redeemAmount, MIN_FUZZ_AMOUNT, MAX_FUZZ_AMOUNT);
        
        // Try to redeem without depositing
        vm.prank(userA);
        vault_arb.approve(address(yzEnforcedComposer_arb), _redeemAmount);
        
        SendParam memory redeemParam = _buildHopParam(address(0), userA, ARB_EID, _redeemAmount);
        
        vm.expectRevert();
        vm.prank(userA);
        yzEnforcedComposer_arb.redeemAndSend(_redeemAmount, redeemParam, userA);
        
        _assertNoStateChange();
    }

    /*//////////////////////////////////////////////////////////////
                            CAP MANAGEMENT FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_SetTVLCap_ValidRange(uint256 _cap) public {
        _cap = bound(_cap, MIN_CAP, MAX_FUZZ_AMOUNT);
        
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(_cap);
        
        assertEq(yzEnforcedComposer_arb.tvlCap(), _cap);
    }

    function testFuzz_SetUserCap_ValidRange(address _user, uint256 _cap) public {
        vm.assume(_user != address(0));
        _cap = bound(_cap, MIN_CAP, MAX_FUZZ_AMOUNT);
        
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(_user, _cap);
        
        assertEq(yzEnforcedComposer_arb.userDepositCap(_user), _cap);
    }

    function testFuzz_SetUserCap_RevertsOnZeroAddress(uint256 _cap) public {
        _cap = bound(_cap, MIN_CAP, MAX_FUZZ_AMOUNT);
        
        vm.expectRevert(YZEnforcedComposer.YZ_ZeroAddress.selector);
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(address(0), _cap);
    }

    function testFuzz_BatchSetUserCaps_ValidInputs(
        address[5] memory _users,
        uint256[5] memory _caps
    ) public {
        // Filter out zero addresses
        address[] memory validUsers = new address[](5);
        uint256[] memory validCaps = new uint256[](5);
        uint256 validCount = 0;
        
        for (uint256 i = 0; i < 5; i++) {
            if (_users[i] != address(0)) {
                validUsers[validCount] = _users[i];
                validCaps[validCount] = bound(_caps[i], MIN_CAP, MAX_FUZZ_AMOUNT);
                validCount++;
            }
        }
        
        if (validCount > 0) {
            // Resize arrays to actual valid count
            address[] memory users = new address[](validCount);
            uint256[] memory caps = new uint256[](validCount);
            
            for (uint256 i = 0; i < validCount; i++) {
                users[i] = validUsers[i];
                caps[i] = validCaps[i];
            }
            
            vm.prank(admin);
            yzEnforcedComposer_arb.batchSetUserCaps(users, caps);
            
            for (uint256 i = 0; i < validCount; i++) {
                assertEq(yzEnforcedComposer_arb.userDepositCap(users[i]), caps[i]);
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                            WHITELIST FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_SetWhitelist_ValidStatus(address _user, bool _status) public {
        vm.assume(_user != address(0));
        
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelistEnabled(true);
        
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelist(_user, _status);
        
        assertEq(yzEnforcedComposer_arb.whitelist(_user), _status);
    }

    function testFuzz_BatchSetWhitelist_ValidInputs(
        address[5] memory _users,
        bool[5] memory _statuses
    ) public {
        // Filter out zero addresses
        address[] memory validUsers = new address[](5);
        bool[] memory validStatuses = new bool[](5);
        uint256 validCount = 0;
        
        for (uint256 i = 0; i < 5; i++) {
            if (_users[i] != address(0)) {
                validUsers[validCount] = _users[i];
                validStatuses[validCount] = _statuses[i];
                validCount++;
            }
        }
        
        if (validCount > 0) {
            // Resize arrays to actual valid count
            address[] memory users = new address[](validCount);
            bool[] memory statuses = new bool[](validCount);
            
            for (uint256 i = 0; i < validCount; i++) {
                users[i] = validUsers[i];
                statuses[i] = validStatuses[i];
            }
            
            vm.prank(admin);
            yzEnforcedComposer_arb.setWhitelistEnabled(true);
            vm.prank(admin);
            yzEnforcedComposer_arb.batchSetWhitelist(users, statuses);
            
            for (uint256 i = 0; i < validCount; i++) {
                assertEq(yzEnforcedComposer_arb.whitelist(users[i]), statuses[i]);
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_SetAdmin_ValidAddress(address _newAdmin) public {
        vm.assume(_newAdmin != address(0));
        vm.assume(_newAdmin != admin);
        
        vm.prank(admin);
        yzEnforcedComposer_arb.setAdmin(_newAdmin);
        
        assertEq(yzEnforcedComposer_arb.admin(), _newAdmin);
    }

    function testFuzz_SetAdmin_RevertsOnZeroAddress(uint256 _unused) public {
        vm.expectRevert(YZEnforcedComposer.YZ_ZeroAddress.selector);
        vm.prank(admin);
        yzEnforcedComposer_arb.setAdmin(address(0));
    }

    function testFuzz_SetAdmin_RevertsOnNonAdmin(address _nonAdmin, address _newAdmin) public {
        vm.assume(_nonAdmin != admin);
        vm.assume(_newAdmin != address(0));
        
        vm.expectRevert(YZEnforcedComposer.YZ_NotAdmin.selector);
        vm.prank(_nonAdmin);
        yzEnforcedComposer_arb.setAdmin(_newAdmin);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTION FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_GetUserDepositInfo_ConsistentWithDeposits(uint256 _userCap, uint256 _depositAmount) public {
        _userCap = bound(_userCap, MIN_CAP, MAX_FUZZ_AMOUNT);
        _depositAmount = bound(_depositAmount, MIN_FUZZ_AMOUNT, _userCap);
        
        _setupUserCap(userA, _userCap);
        _executeSuccessfulDeposit(userA, _depositAmount);
        
        (uint256 deposit, uint256 cap, uint256 remaining) = yzEnforcedComposer_arb.getUserDepositInfo(userA);
        
        assertEq(deposit, _depositAmount);
        assertEq(cap, _userCap);
        assertEq(remaining, _userCap - _depositAmount);
    }

    function testFuzz_CanDeposit_ConsistentWithActualDeposit(uint256 _userCap, uint256 _tvlCap, uint256 _testAmount) public {
        _userCap = bound(_userCap, MIN_CAP, MAX_FUZZ_AMOUNT);
        _tvlCap = bound(_tvlCap, MIN_CAP, MAX_FUZZ_AMOUNT);
        _testAmount = bound(_testAmount, MIN_FUZZ_AMOUNT, MAX_FUZZ_AMOUNT);
        
        _setupUserCap(userA, _userCap);
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(_tvlCap);
        
        (bool canDeposit, ) = yzEnforcedComposer_arb.canDeposit(userA, _testAmount);
        
        // Test the prediction by actually attempting the deposit
        _fundLocalFromHub(userA, _testAmount);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), _testAmount);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, _testAmount);
        
        if (canDeposit) {
            vm.prank(userA);
            yzEnforcedComposer_arb.depositAndSend(_testAmount, sendParam, userA);
            _assertDepositSuccess(userA, _testAmount, _testAmount);
        } else {
            vm.expectRevert();
            vm.prank(userA);
            yzEnforcedComposer_arb.depositAndSend(_testAmount, sendParam, userA);
            _assertNoStateChange();
        }
    }

    /*//////////////////////////////////////////////////////////////
                            EMERGENCY FUNCTION FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_EmergencyWithdraw_Assets_ValidAmount(uint256 _withdrawAmount) public {
        _withdrawAmount = bound(_withdrawAmount, MIN_FUZZ_AMOUNT, MAX_FUZZ_AMOUNT);
        
        _fundLocalFromHub(address(yzEnforcedComposer_arb), _withdrawAmount);
        
        vm.prank(admin);
        yzEnforcedComposer_arb.emergencyWithdraw(_withdrawAmount, recipient);
        
        assertEq(assetOFT_arb.balanceOf(recipient), _withdrawAmount);
    }

    function testFuzz_EmergencyWithdraw_Assets_RevertsOnZeroAddress(uint256 _withdrawAmount) public {
        _withdrawAmount = bound(_withdrawAmount, MIN_FUZZ_AMOUNT, MAX_FUZZ_AMOUNT);
        
        _fundLocalFromHub(address(yzEnforcedComposer_arb), _withdrawAmount);
        
        vm.expectRevert(YZEnforcedComposer.YZ_ZeroAddress.selector);
        vm.prank(admin);
        yzEnforcedComposer_arb.emergencyWithdraw(_withdrawAmount, address(0));
    }

    function testFuzz_EmergencyWithdraw_Assets_RevertsOnZeroAmount(uint256 _unused) public {
        vm.expectRevert("Zero amount");
        vm.prank(admin);
        yzEnforcedComposer_arb.emergencyWithdraw(0, recipient);
    }

    function testFuzz_EmergencyWithdraw_Assets_RevertsOnInsufficientBalance(uint256 _withdrawAmount) public {
        _withdrawAmount = bound(_withdrawAmount, MIN_FUZZ_AMOUNT, MAX_FUZZ_AMOUNT);
        
        vm.expectRevert("Insufficient balance");
        vm.prank(admin);
        yzEnforcedComposer_arb.emergencyWithdraw(_withdrawAmount, recipient);
    }

    function testFuzz_EmergencyWithdraw_RevertsOnNonAdmin(address _nonAdmin, uint256 _withdrawAmount) public {
        vm.assume(_nonAdmin != admin);
        _withdrawAmount = bound(_withdrawAmount, MIN_FUZZ_AMOUNT, MAX_FUZZ_AMOUNT);
        
        _fundLocalFromHub(address(yzEnforcedComposer_arb), _withdrawAmount);
        
        vm.expectRevert(YZEnforcedComposer.YZ_NotAdmin.selector);
        vm.prank(_nonAdmin);
        yzEnforcedComposer_arb.emergencyWithdraw(_withdrawAmount, recipient);
    }

    /*//////////////////////////////////////////////////////////////
                            HELPERS
    //////////////////////////////////////////////////////////////*/

    function _setupDefaultCaps() internal {
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(MAX_FUZZ_AMOUNT);
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

    function _assertNoStateChange() internal {
        assertEq(vault_arb.totalAssets(), 0);
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), 0);
    }
}