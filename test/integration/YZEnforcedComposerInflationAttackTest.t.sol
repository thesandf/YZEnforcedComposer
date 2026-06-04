// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {YZEnforcedComposer} from "../../src/YZEnforcedComposer.sol";
import "../unit/YZEnforcedComposerBase.t.sol";

contract YZEnforcedComposerInflationAttackTest is YZEnforcedComposerBase {
    function test_InflationAttack_ShareSupply_NotVulnerable() public {
        // Setup TVL cap
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(100 ether);

        // Normal deposit
        _fundLocalFromHub(userA, 50 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);

        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);

        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(50 ether, sendParam, userA);

        uint256 userShares = vault_arb.balanceOf(userA);
        assertEq(userShares, 50 ether); // 1:1 initially

        // Try to inflate share supply through malicious minting
        // This should not be possible with standard ERC4626 vault
        vm.prank(userA);
        vm.expectRevert();
        vault_arb.mint(100 ether, userA); // Should fail - only vault can mint

        // Verify share supply integrity
        assertEq(vault_arb.balanceOf(userA), 50 ether);
        assertEq(vault_arb.totalSupply(), 50 ether);
    }

    function test_InflationAttack_AssetSupply_NotVulnerable() public {
        // Normal deposit
        _fundLocalFromHub(userA, 100 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 100 ether);

        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 100 ether);

        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(100 ether, sendParam, userA);

        // Try to inflate asset supply through malicious minting
        vm.prank(userA);
        (bool success,) = address(assetOFT_arb).call(abi.encodeWithSignature("mint(address,uint256)", userA, 100 ether));
        assertFalse(success);

        // Verify asset supply integrity
        assertEq(assetOFT_arb.balanceOf(userA), 0); // No additional assets
        assertEq(vault_arb.totalAssets(), 100 ether); // TVL unchanged
    }

    function test_InflationAttack_TVLManipulation_NotVulnerable() public {
        // Setup TVL cap
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(100 ether);

        // Normal deposit
        _fundLocalFromHub(userA, 50 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);

        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);

        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(50 ether, sendParam, userA);

        // Try to manipulate TVL through external calls
        // This should not be possible with standard vault implementation
        vm.prank(userA);
        (bool success,) = address(vault_arb).call(abi.encodeWithSignature("setTotalAssets(uint256)", 200 ether));
        assertFalse(success);

        // Try to deposit more - should still be rejected due to actual TVL
        _fundLocalFromHub(userA, 60 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 60 ether);

        sendParam = _buildHopParam(address(0), userA, ARB_EID, 60 ether);

        vm.prank(userA);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend(60 ether, sendParam, userA);

        // Verify TVL integrity
        assertEq(vault_arb.totalAssets(), 50 ether);
    }

    function test_InflationAttack_UserDepositTracking_NotVulnerable() public {
        // Setup user cap
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(userA, 100 ether);

        // Normal deposit
        _fundLocalFromHub(userA, 50 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);

        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);

        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(50 ether, sendParam, userA);

        // Try to manipulate user deposit tracking
        // Only admin can call exposed_setUserDeposit
        vm.prank(userA);
        (bool success,) = address(yzEnforcedComposer_arb)
            .call(abi.encodeWithSignature("exposed_setUserDeposit(address,uint256)", userA, 10 ether));
        assertFalse(success);

        // Try to deposit more - should still be rejected due to actual tracking
        _fundLocalFromHub(userA, 60 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 60 ether);

        sendParam = _buildHopParam(address(0), userA, ARB_EID, 60 ether);

        vm.prank(userA);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend(60 ether, sendParam, userA);

        // Verify tracking integrity
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), 50 ether);
    }

    function test_InflationAttack_SharePriceManipulation_NotVulnerable() public {
        // Normal deposit
        _fundLocalFromHub(userA, 100 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 100 ether);

        SendParam memory depositParam = _buildHopParam(address(0), userA, ARB_EID, 100 ether);

        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(100 ether, depositParam, userA);

        // Try to manipulate share price
        vm.prank(userA);
        (bool success,) = address(vault_arb).call(abi.encodeWithSignature("setPricePerShare(uint256)", 2 ether));
        assertFalse(success);

        // Try to redeem - should work with actual price
        vm.prank(userA);
        vault_arb.approve(address(yzEnforcedComposer_arb), 50 ether);

        SendParam memory redeemParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);

        vm.prank(userA);
        yzEnforcedComposer_arb.redeemAndSend(50 ether, redeemParam, userA);

        // Verify redemption with actual share price
        uint256 receivedAssets = assetOFT_arb.balanceOf(userA);
        assertEq(receivedAssets, 50 ether); // 1:1 price
    }

    function test_InflationAttack_MultipleUserAttack_NotVulnerable() public {
        // Setup caps
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(200 ether);
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(userA, 100 ether);
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(userB, 100 ether);

        // User A deposits
        _fundLocalFromHub(userA, 100 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 100 ether);

        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 100 ether);

        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(100 ether, sendParam, userA);

        // User B deposits
        _fundLocalFromHub(userB, 100 ether);
        vm.prank(userB);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 100 ether);

        sendParam = _buildHopParam(address(0), userB, ARB_EID, 100 ether);

        vm.prank(userB);
        yzEnforcedComposer_arb.depositAndSend(100 ether, sendParam, userB);

        // Try to inflate through coordinated attack
        // Both users try to deposit more simultaneously
        _fundLocalFromHub(userA, 10 ether);
        _fundLocalFromHub(userB, 10 ether);

        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 10 ether);
        vm.prank(userB);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 10 ether);

        sendParam = _buildHopParam(address(0), userA, ARB_EID, 10 ether);
        vm.prank(userA);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend(10 ether, sendParam, userA);

        sendParam = _buildHopParam(address(0), userB, ARB_EID, 10 ether);
        vm.prank(userB);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend(10 ether, sendParam, userB);

        // Verify caps still enforced
        assertEq(vault_arb.totalAssets(), 200 ether);
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), 100 ether);
        assertEq(yzEnforcedComposer_arb.userDeposits(userB), 100 ether);
    }

    function test_InflationAttack_WhitelistBypass_NotVulnerable() public {
        // Setup whitelist
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelistEnabled(true);
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelist(userA, true);

        // User A deposits (whitelisted)
        _fundLocalFromHub(userA, 50 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);

        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);

        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(50 ether, sendParam, userA);

        // Try to bypass whitelist through address manipulation
        address manipulatedAddress = address(uint160(uint256(keccak256(abi.encodePacked(userA)))) ^ 1);

        _fundLocalFromHub(manipulatedAddress, 30 ether);
        vm.prank(manipulatedAddress);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 30 ether);

        sendParam = _buildHopParam(address(0), manipulatedAddress, ARB_EID, 30 ether);

        vm.prank(manipulatedAddress);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend(30 ether, sendParam, manipulatedAddress);

        // Verify whitelist still enforced
        assertEq(vault_arb.totalAssets(), 50 ether);
        assertEq(yzEnforcedComposer_arb.userDeposits(manipulatedAddress), 0);
    }

    function test_InflationAttack_PauseBypass_NotVulnerable() public {
        // Pause deposits
        vm.prank(admin);
        yzEnforcedComposer_arb.pauseDeposits();

        // Try to bypass pause through different chains
        _fundLocalFromHub(userA, 50 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);

        SendParam memory sendParam = _buildHopParam(address(0), userA, ETH_EID, 50 ether);

        vm.prank(userA);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend(50 ether, sendParam, userA);

        sendParam = _buildHopParam(address(0), userA, POL_EID, 50 ether);

        vm.prank(userA);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend(50 ether, sendParam, userA);

        sendParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);

        vm.prank(userA);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend(50 ether, sendParam, userA);

        // Verify pause enforced across all chains
        assertEq(vault_arb.totalAssets(), 0);
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), 0);
    }

    function test_InflationAttack_CapManipulation_NotVulnerable() public {
        // Setup caps
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(100 ether);
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(userA, 50 ether);

        // Normal deposit
        _fundLocalFromHub(userA, 50 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);

        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);

        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(50 ether, sendParam, userA);

        // Try to manipulate caps through admin functions
        vm.prank(userA);
        vm.expectRevert();
        yzEnforcedComposer_arb.setTVLCap(200 ether); // Should fail - not admin

        vm.prank(userA);
        vm.expectRevert();
        yzEnforcedComposer_arb.setUserCap(userA, 100 ether); // Should fail - not admin

        // Try to deposit more - should still be rejected
        _fundLocalFromHub(userA, 10 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 10 ether);

        sendParam = _buildHopParam(address(0), userA, ARB_EID, 10 ether);

        vm.prank(userA);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend(10 ether, sendParam, userA);

        // Verify caps integrity
        assertEq(yzEnforcedComposer_arb.tvlCap(), 100 ether);
        assertEq(yzEnforcedComposer_arb.userDepositCap(userA), 50 ether);
        assertEq(vault_arb.totalAssets(), 50 ether);
    }

    function test_InflationAttack_EmergencyWithdraw_NotVulnerable() public {
        _fundLocalFromHub(address(yzEnforcedComposer_arb), 100 ether);

        // Try to manipulate emergency withdraw
        vm.prank(userA);
        vm.expectRevert();
        yzEnforcedComposer_arb.emergencyWithdraw(50 ether, recipient); // Should fail - not admin

        vm.prank(userA);
        vm.expectRevert();
        yzEnforcedComposer_arb.emergencyWithdrawShares(50 ether, recipient); // Should fail - not admin

        vm.prank(userA);
        vm.expectRevert();
        yzEnforcedComposer_arb.emergencyWithdrawNative(1 ether, payable(recipient)); // Should fail - not admin

        // Verify emergency functions only accessible by admin
        assertEq(assetOFT_arb.balanceOf(recipient), 0);
        assertEq(vault_arb.balanceOf(recipient), 0);
        assertEq(recipient.balance, 0);
    }
}
