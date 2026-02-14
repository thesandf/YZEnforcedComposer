// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import "../YieldZeroBaseTest.t.sol";
import "../../src/errors/Errors.sol";

contract YieldZeroVaultTest is YieldZeroBaseTest {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_SetComposer_Success() public {
        address newComposer = makeAddr("newComposer");
        vault_arb.setComposer(newComposer);
        assertEq(vault_arb.composer(), newComposer);
    }

    function test_SetComposer_Revert_NotConfigManager() public {
        address newComposer = makeAddr("newComposer");
        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSelector(YZAccessControl_CallerNotConfigManager.selector));
        vault_arb.setComposer(newComposer);
    }

    function test_SetComposer_Revert_ZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(YZVault_InvalidComposer.selector));
        vault_arb.setComposer(address(0));
    }

    function test_SetPaused_Success() public {
        vault_arb.setPaused(true);
        assertTrue(vault_arb.isPaused());
        vault_arb.setPaused(false);
        assertFalse(vault_arb.isPaused());
    }

    function test_SetPaused_Revert_NotConfigManager() public {
        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSelector(YZAccessControl_CallerNotConfigManager.selector));
        vault_arb.setPaused(true);
    }

    function test_Deposit_Success() public {
        uint256 amount = 100 * 10 ** 18;
        _fundLocalFromHub(address(yieldZeroComposer_arb), amount);

        vm.prank(address(yieldZeroComposer_arb));
        uint256 shares = vault_arb.deposit(amount, userA);

        assertEq(shares, amount);
        assertEq(vault_arb.balanceOf(userA), amount);
        assertEq(vault_arb.totalAssets(), amount);
    }

    function test_Deposit_Revert_NotComposer() public {
        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSelector(YZVault_CallerNotComposer.selector));
        vault_arb.deposit(TOKENS_TO_SEND, userA);
    }

    function test_Deposit_Revert_WhenPaused() public {
        vault_arb.setPaused(true);
        vm.prank(address(yieldZeroComposer_arb));
        vm.expectRevert(abi.encodeWithSelector(YZVault_Paused.selector));
        vault_arb.deposit(TOKENS_TO_SEND, userA);
    }

    function test_Deposit_Revert_ZeroAmount() public {
        vm.prank(address(yieldZeroComposer_arb));
        vm.expectRevert(abi.encodeWithSelector(YZVault_ZeroAmount.selector));
        vault_arb.deposit(0, userA);
    }

    function test_Deposit_Revert_InvalidReceiver() public {
        vm.prank(address(yieldZeroComposer_arb));
        vm.expectRevert(abi.encodeWithSelector(YZVault_ZeroReceiver.selector));
        vault_arb.deposit(TOKENS_TO_SEND, address(0));
    }

    function test_Redeem_Success() public {
        uint256 amount = 100 * 10 ** 18;
        _fundLocalFromHub(address(yieldZeroComposer_arb), amount);

        vm.startPrank(address(yieldZeroComposer_arb));
        vault_arb.deposit(amount, address(yieldZeroComposer_arb));

        uint256 assets = vault_arb.redeem(amount, userA, address(yieldZeroComposer_arb));
        vm.stopPrank();

        assertEq(assets, amount);
        assertEq(assetOFT_arb.balanceOf(userA), amount);
        assertEq(vault_arb.totalSupply(), 0);
    }

    function test_Redeem_Revert_NotComposer() public {
        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSelector(YZVault_CallerNotComposer.selector));
        vault_arb.redeem(TOKENS_TO_SEND, userA, userA);
    }

    function test_Redeem_Revert_WhenPaused() public {
        vault_arb.setPaused(true);
        vm.prank(address(yieldZeroComposer_arb));
        vm.expectRevert(abi.encodeWithSelector(YZVault_Paused.selector));
        vault_arb.redeem(TOKENS_TO_SEND, userA, userA);
    }

    function test_Redeem_Revert_ZeroShares() public {
        vm.prank(address(yieldZeroComposer_arb));
        vm.expectRevert(abi.encodeWithSelector(YZVault_ZeroShares.selector));
        vault_arb.redeem(0, userA, userA);
    }

    function test_Redeem_Revert_InvalidReceiver() public {
        vm.prank(address(yieldZeroComposer_arb));
        vm.expectRevert(abi.encodeWithSelector(YZVault_ZeroReceiver.selector));
        vault_arb.redeem(TOKENS_TO_SEND, address(0), userA);
    }

    function test_TotalAssets() public {
        uint256 amount = 50 * 10 ** 18;
        _fundLocalFromHub(address(vault_arb), amount);
        assertEq(vault_arb.totalAssets(), amount);
    }

    function test_PreviewFunctions() public {
        uint256 amount = 100 ether;
        assertEq(vault_arb.previewDeposit(amount), amount);
        assertEq(vault_arb.previewMint(amount), amount);
        assertEq(vault_arb.previewWithdraw(amount), amount);
        assertEq(vault_arb.previewRedeem(amount), amount);
    }

    function test_GetVaultStats() public {
        uint256 amount = 100 * 10 ** 18;
        _fundLocalFromHub(address(yieldZeroComposer_arb), amount);

        vm.prank(address(yieldZeroComposer_arb));
        vault_arb.deposit(amount, userA);

        (uint256 totalAssets_, uint256 totalShares_, uint256 totalYield_) = vault_arb.getVaultStats();
        assertEq(totalAssets_, amount);
        assertEq(totalShares_, amount);
        assertEq(totalYield_, 0);
    }

    // Fuzzing Tests
    function testFuzz_Deposit_Success(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 1000 ether);
        _fundLocalFromHub(address(yieldZeroComposer_arb), amount);

        vm.prank(address(yieldZeroComposer_arb));
        uint256 shares = vault_arb.deposit(amount, userA);

        assertEq(shares, amount);
        assertEq(vault_arb.balanceOf(userA), amount);
        assertEq(vault_arb.totalAssets(), amount);
    }

    function testFuzz_Redeem_Success(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 100 ether);
        _fundLocalFromHub(address(yieldZeroComposer_arb), amount);

        vm.startPrank(address(yieldZeroComposer_arb));
        vault_arb.deposit(amount, address(yieldZeroComposer_arb));

        uint256 assets = vault_arb.redeem(amount, userA, address(yieldZeroComposer_arb));
        vm.stopPrank();

        assertEq(assets, amount);
        assertEq(assetOFT_arb.balanceOf(userA), amount);
        assertEq(vault_arb.totalSupply(), 0);
    }

    function testFuzz_EmergencyWithdraw_Success(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 100 ether);
        _fundLocalFromHub(address(vault_arb), amount);

        address recipient = makeAddr("recipient");
        vault_arb.emergencyWithdraw(amount, recipient);

        assertEq(assetOFT_arb.balanceOf(recipient), amount);
    }

    function testFuzz_TotalAssets(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 1000 ether);
        _fundLocalFromHub(address(vault_arb), amount);
        assertEq(vault_arb.totalAssets(), amount);
    }

    function testFuzz_PreviewFunctions(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 1000 ether);
        assertEq(vault_arb.previewDeposit(amount), amount);
        assertEq(vault_arb.previewMint(amount), amount);
        assertEq(vault_arb.previewWithdraw(amount), amount);
        assertEq(vault_arb.previewRedeem(amount), amount);
    }

    function testFuzz_GetVaultStats(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 1000 ether);
        _fundLocalFromHub(address(yieldZeroComposer_arb), amount);

        vm.prank(address(yieldZeroComposer_arb));
        vault_arb.deposit(amount, userA);

        (uint256 totalAssets_, uint256 totalShares_, uint256 totalYield_) = vault_arb.getVaultStats();
        assertEq(totalAssets_, amount);
        assertEq(totalShares_, amount);
        assertEq(totalYield_, 0);
    }
}
