// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import "../YieldZeroBaseTest.t.sol";
import {RateLimiter} from "../../src/security/RateLimiter.sol";
import "../../src/errors/Errors.sol";

contract YieldZeroComposerTest is YieldZeroBaseTest {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_SetMaxDepositSize_Success() public {
        uint256 newMax = 1000 ether;
        yieldZeroComposer_arb.setMaxDepositSize(newMax);
        assertEq(yieldZeroComposer_arb.maxDepositSize(), newMax);
    }

    function test_SetMaxDepositSize_Revert_NotConfigManager() public {
        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSelector(YZComposer_CallerNotConfigManager.selector));
        yieldZeroComposer_arb.setMaxDepositSize(1000 ether);
    }

    function test_SetMinDepositSize_Success() public {
        uint256 newMin = 0.5 ether;
        yieldZeroComposer_arb.setMinDepositSize(newMin);
        assertEq(yieldZeroComposer_arb.minDepositSize(), newMin);
    }

    function test_SetMinDepositSize_Revert_NotConfigManager() public {
        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSelector(YZComposer_CallerNotConfigManager.selector));
        yieldZeroComposer_arb.setMinDepositSize(0.5 ether);
    }

    function test_SetRateLimiter_Success() public {
        address newRateLimiter = makeAddr("newRateLimiter");
        yieldZeroComposer_arb.setRateLimiter(newRateLimiter);
        assertEq(yieldZeroComposer_arb.rateLimiter(), newRateLimiter);
    }

    function test_SetRateLimiter_Revert_NotConfigManager() public {
        address newRateLimiter = makeAddr("newRateLimiter");
        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSelector(YZComposer_CallerNotConfigManager.selector));
        yieldZeroComposer_arb.setRateLimiter(newRateLimiter);
    }

    function test_InitiateDepositAndSend_Revert_BelowMin() public {
        uint256 minSize = 1 ether;
        yieldZeroComposer_arb.setMinDepositSize(minSize);

        uint256 amount = minSize - 1;
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, amount);

        _fundLocalFromHub(userA, amount);
        vm.prank(userA);
        assetOFT_arb.approve(address(yieldZeroComposer_arb), amount);

        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSelector(YZComposer_BelowMinimum.selector));
        yieldZeroComposer_arb.initiateDepositAndSend(amount, 0, sendParam, userA);
    }

    function test_InitiateDepositAndSend_Revert_AboveMax() public {
        uint256 amount = 100 ether;
        yieldZeroComposer_arb.setMaxDepositSize(amount - 1);

        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, amount);

        _fundLocalFromHub(userA, amount);
        vm.prank(userA);
        assetOFT_arb.approve(address(yieldZeroComposer_arb), amount);

        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSelector(YZComposer_AboveMaximum.selector));
        yieldZeroComposer_arb.initiateDepositAndSend(amount, 0, sendParam, userA);
    }

    function test_InitiateRedeemAndSend_Revert_BelowMin() public {
        uint256 minSize = 1 ether;
        yieldZeroComposer_arb.setMinDepositSize(minSize);

        uint256 amount = minSize - 1;
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, amount);

        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSelector(YZComposer_ZeroAmount.selector)); // If amount is 0
        yieldZeroComposer_arb.initiateRedeemAndSend(0, 0, sendParam, userA);

        if (amount > 0) {
            vm.prank(userA);
            vm.expectRevert(abi.encodeWithSelector(YZComposer_BelowMinimum.selector));
            yieldZeroComposer_arb.initiateRedeemAndSend(amount, 0, sendParam, userA);
        }
    }

    function test_EmergencyWithdraw_Success() public {
        uint256 amount = 10 ether;
        _fundLocalFromHub(address(yieldZeroComposer_arb), amount);

        address recipient = makeAddr("recipient");
        yieldZeroComposer_arb.emergencyWithdraw(amount, recipient);

        assertEq(assetOFT_arb.balanceOf(recipient), amount);
    }

    function test_EmergencyWithdraw_Revert_NotOwner() public {
        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", userA));
        yieldZeroComposer_arb.emergencyWithdraw(1 ether, userA);
    }

    function test_GetTotalValueLocked() public {
        uint256 amount = 2 ether;
        _fundLocalFromHub(userA, amount);
        vm.prank(userA);
        assetOFT_arb.approve(address(yieldZeroComposer_arb), amount);

        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, amount);
        uint256 expectedShares = vault_arb.previewDeposit(amount);

        vm.prank(userA);
        yieldZeroComposer_arb.initiateDepositAndSend(amount, expectedShares, sendParam, userA);

        assertEq(yieldZeroComposer_arb.getTotalValueLocked(), amount);
    }

    function test_GetUserSharesAndAssets() public {
        uint256 amount = 2 ether;
        _fundLocalFromHub(userA, amount);
        vm.prank(userA);
        assetOFT_arb.approve(address(yieldZeroComposer_arb), amount);

        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, amount);
        uint256 expectedShares = vault_arb.previewDeposit(amount);

        vm.prank(userA);
        yieldZeroComposer_arb.initiateDepositAndSend(amount, expectedShares, sendParam, userA);

        assertEq(yieldZeroComposer_arb.getUserShares(userA), expectedShares);
        assertEq(yieldZeroComposer_arb.getUserAssets(userA), amount);
    }

    // Fuzzing Tests
    function testFuzz_InitiateDepositAndSend_Success(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 1000 ether);
        vm.assume(amount >= yieldZeroComposer_arb.minDepositSize());
        vm.assume(amount <= yieldZeroComposer_arb.maxDepositSize());

        _fundLocalFromHub(userA, amount);
        vm.prank(userA);
        assetOFT_arb.approve(address(yieldZeroComposer_arb), amount);

        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, amount);
        uint256 expectedShares = vault_arb.previewDeposit(amount);

        vm.prank(userA);
        yieldZeroComposer_arb.initiateDepositAndSend(amount, expectedShares, sendParam, userA);

        assertEq(vault_arb.totalAssets(), amount);
        assertEq(vault_arb.balanceOf(userA), expectedShares);
    }

    function testFuzz_SetMaxDepositSize_Success(uint256 newMax) public {
        vm.assume(newMax > 0 && newMax <= type(uint256).max);
        yieldZeroComposer_arb.setMaxDepositSize(newMax);
        assertEq(yieldZeroComposer_arb.maxDepositSize(), newMax);
    }

    function testFuzz_SetMinDepositSize_Success(uint256 newMin) public {
        vm.assume(newMin > 0 && newMin <= 100 ether);
        yieldZeroComposer_arb.setMinDepositSize(newMin);
        assertEq(yieldZeroComposer_arb.minDepositSize(), newMin);
    }

    function testFuzz_EmergencyWithdraw_Success(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 100 ether);
        _fundLocalFromHub(address(yieldZeroComposer_arb), amount);

        address recipient = makeAddr("recipient");
        yieldZeroComposer_arb.emergencyWithdraw(amount, recipient);

        assertEq(assetOFT_arb.balanceOf(recipient), amount);
    }


    function _addressToBytes32(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    function _buildHopParam(address recipient, address composer, uint32 _dstEid, uint256 amount)
        internal
        pure
        override
        returns (SendParam memory)
    {
        if (recipient == address(0)) {
            recipient = composer;
        }
        return SendParam({
            dstEid: _dstEid,
            to: _addressToBytes32(recipient),
            amountLD: amount,
            minAmountLD: (amount * 99) / 100,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });
    }
}
