// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {YZEnforcedComposer} from "../../src/YZEnforcedComposer.sol";
import "./YZEnforcedComposerBase.t.sol";

contract YZEnforcedComposerUserCapTest is YZEnforcedComposerBase {
    function test_SetUserCap_UpdatesCap() public {
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit YZEnforcedComposer.UserCapUpdated(userA, 0, 50 ether);
        yzEnforcedComposer_arb.setUserCap(userA, 50 ether);

        assertEq(yzEnforcedComposer_arb.userDepositCap(userA), 50 ether);
    }

    function test_SetUserCap_RevertsOnZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(YZEnforcedComposer.YZ_ZeroAddress.selector);
        yzEnforcedComposer_arb.setUserCap(address(0), 50 ether);
    }

    function test_BatchSetUserCaps_UpdatesMultiple() public {
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

        vm.prank(admin);
        vm.expectRevert(YZEnforcedComposer.YZ_LengthMismatch.selector);
        yzEnforcedComposer_arb.batchSetUserCaps(users, caps);
    }

    function test_Deposit_RevertsWhenUserCapExceeded() public {
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(userA, 50 ether);

        _fundLocalFromHub(userA, 60 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 60 ether);

        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 60 ether);

        vm.prank(userA);
        vm.expectRevert(
            abi.encodeWithSelector(YZEnforcedComposer.YZ_UserCapExceeded.selector, userA, 0, 60 ether, 50 ether)
        );
        yzEnforcedComposer_arb.depositAndSend(60 ether, sendParam, userA);
    }

    function test_Deposit_SucceedsWhenWithinUserCap() public {
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(userA, 100 ether);

        _fundLocalFromHub(userA, 50 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);

        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);

        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(50 ether, sendParam, userA);

        assertEq(vault_arb.totalAssets(), 50 ether);
        assertEq(yzEnforcedComposer_arb.getUserShares(userA), 50 ether);
    }

    function test_Deposit_UpdatesUserTrackingAfterSuccess() public {
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(userA, 100 ether);

        _fundLocalFromHub(userA, 30 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 30 ether);

        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 30 ether);

        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(30 ether, sendParam, userA);

        assertEq(yzEnforcedComposer_arb.getUserShares(userA), 30 ether);

        _fundLocalFromHub(userA, 20 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 20 ether);

        sendParam = _buildHopParam(address(0), userA, ARB_EID, 20 ether);

        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(20 ether, sendParam, userA);

        assertEq(yzEnforcedComposer_arb.getUserShares(userA), 50 ether);
    }

    function test_Deposit_DoesNotUpdateTrackingIfReverts() public {
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(userA, 40 ether);

        _fundLocalFromHub(userA, 50 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);

        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);

        vm.prank(userA);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend(50 ether, sendParam, userA);

        assertEq(yzEnforcedComposer_arb.getUserShares(userA), 0);
    }

    function testFuzz_SetUserCap(address _user, uint256 _cap) public {
        vm.assume(_user != address(0));
        vm.assume(_cap < type(uint256).max / 2);
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(_user, _cap);
        assertEq(yzEnforcedComposer_arb.userDepositCap(_user), _cap);
    }

    function testFuzz_UserCap_NeverExceeded(uint256 _amount) public {
        _amount = bound(_amount, 1, 100 ether);

        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(userA, 50 ether);

        _fundLocalFromHub(userA, _amount);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), _amount);

        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, _amount);

        vm.prank(userA);
        if (_amount > 50 ether) {
            vm.expectRevert();
        }
        yzEnforcedComposer_arb.depositAndSend(_amount, sendParam, userA);

        if (_amount <= 50 ether) {
            assertLe(yzEnforcedComposer_arb.getUserShares(userA), 50 ether);
        }
    }
}
