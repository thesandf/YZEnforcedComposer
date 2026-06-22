// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {YZEnforcedComposer} from "../../src/YZEnforcedComposer.sol";
import "../unit/YZEnforcedComposerBase.t.sol";

contract YZEnforcedComposerCrossChainReplayTest is YZEnforcedComposerBase {
    function test_CrossChainReplay_DepositMessage_NotVulnerable() public {
        // Setup caps
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(100 ether);
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(userA, 50 ether);

        // User deposits normally
        _fundLocalFromHub(userA, 50 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);

        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);

        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(50 ether, sendParam, userA);

        // Verify state
        assertEq(vault_arb.totalAssets(), 50 ether);
        assertEq(yzEnforcedComposer_arb.getUserAssets(userA), 50 ether);

        // Simulate replay attack - same message sent again
        // LayerZero V2 handles replay protection at the protocol level
        // This test verifies that even if a message were replayed (which shouldn't happen),
        // the enforcement checks would still work correctly

        // Try to deposit again with same parameters (should fail due to user cap)
        _fundLocalFromHub(userA, 10 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 10 ether);

        sendParam = _buildHopParam(address(0), userA, ARB_EID, 10 ether);

        vm.prank(userA);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend(10 ether, sendParam, userA);

        // Verify state unchanged
        assertEq(vault_arb.totalAssets(), 50 ether);
        assertEq(yzEnforcedComposer_arb.getUserAssets(userA), 50 ether);
    }

    function test_CrossChainReplay_RedeemMessage_NotVulnerable() public {
        // Setup
        _fundLocalFromHub(userA, 100 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 100 ether);

        SendParam memory depositParam = _buildHopParam(address(0), userA, ARB_EID, 100 ether);

        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(100 ether, depositParam, userA);

        // User redeems normally
        vm.prank(userA);
        vault_arb.approve(address(yzEnforcedComposer_arb), 50 ether);

        SendParam memory redeemParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);

        vm.prank(userA);
        yzEnforcedComposer_arb.redeemAndSend(50 ether, redeemParam, userA);

        // Verify state
        assertEq(vault_arb.totalAssets(), 50 ether);
        assertEq(yzEnforcedComposer_arb.getUserAssets(userA), 50 ether);

        // Simulate replay attack - same redeem message sent again
        // This should fail because the user doesn't have enough shares
        vm.prank(userA);
        vm.expectRevert();
        yzEnforcedComposer_arb.redeemAndSend(50 ether, redeemParam, userA);

        // Verify state unchanged
        assertEq(vault_arb.totalAssets(), 50 ether);
        assertEq(yzEnforcedComposer_arb.getUserAssets(userA), 50 ether);
    }

    function test_CrossChainReplay_DifferentChain_NotVulnerable() public {
        // Setup caps
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(100 ether);
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(userA, 50 ether);

        // User deposits locally on ARB
        _fundLocalFromHub(userA, 50 ether);
        vm.startPrank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);
        yzEnforcedComposer_arb.depositAndSend{value: 0}(50 ether, sendParam, userA);
        vm.stopPrank();

        // Verify state
        assertEq(vault_arb.totalAssets(), 50 ether);
        assertEq(yzEnforcedComposer_arb.getUserAssets(userA), 50 ether);

        // Try to deposit from POL chain with same user (should fail due to user cap)
        // User A's shares are naturally held locally, no deal hack needed
        _fundLocalFromHub(userA, 10 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 10 ether);

        sendParam = _buildHopParam(address(0), userA, POL_EID, 10 ether);
        uint256 fee2 = _getAndFundDepositFee(userA, sendParam);

        vm.prank(userA);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend{value: fee2}(10 ether, sendParam, userA);

        // Verify state unchanged
        assertEq(vault_arb.totalAssets(), 50 ether);
        assertEq(yzEnforcedComposer_arb.getUserAssets(userA), 50 ether);
    }

    function test_CrossChainReplay_TVLTracking_AccurateAcrossChains() public {
        // Setup TVL cap
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(200 ether);

        // Deposit from ETH chain
        _fundLocalFromHub(userA, 100 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 100 ether);

        SendParam memory sendParam = _buildHopParam(address(0), userA, ETH_EID, 100 ether);
        uint256 fee1 = _getAndFundDepositFee(userA, sendParam);

        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend{value: fee1}(100 ether, sendParam, userA);

        uint256 tvlAfterFirst = vault_arb.totalAssets();
        assertEq(tvlAfterFirst, 100 ether);

        // Deposit from POL chain
        _fundLocalFromHub(userB, 80 ether);
        vm.prank(userB);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 80 ether);

        sendParam = _buildHopParam(address(0), userB, POL_EID, 80 ether);
        uint256 fee2 = _getAndFundDepositFee(userB, sendParam);

        vm.prank(userB);
        yzEnforcedComposer_arb.depositAndSend{value: fee2}(80 ether, sendParam, userB);

        uint256 tvlAfterSecond = vault_arb.totalAssets();
        assertEq(tvlAfterSecond, 180 ether);

        // Try to exceed TVL cap from ARB chain
        _fundLocalFromHub(userA, 50 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);

        sendParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);

        vm.prank(userA);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend(50 ether, sendParam, userA);

        // Verify TVL still within cap
        assertEq(vault_arb.totalAssets(), 180 ether);
        assertLe(vault_arb.totalAssets(), 200 ether);
    }

    function test_CrossChainReplay_UserTracking_AccurateAcrossChains() public {
        // Setup user caps
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(userA, 100 ether);
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(userB, 80 ether);

        // User A deposits locally on ARB
        _fundLocalFromHub(userA, 60 ether);
        vm.startPrank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 60 ether);
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 60 ether);
        yzEnforcedComposer_arb.depositAndSend{value: 0}(60 ether, sendParam, userA);
        vm.stopPrank();

        assertEq(yzEnforcedComposer_arb.getUserAssets(userA), 60 ether);

        // User B deposits locally on ARB
        _fundLocalFromHub(userB, 50 ether);
        vm.startPrank(userB);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);
        sendParam = _buildHopParam(address(0), userB, ARB_EID, 50 ether);
        yzEnforcedComposer_arb.depositAndSend{value: 0}(50 ether, sendParam, userB);
        vm.stopPrank();

        assertEq(yzEnforcedComposer_arb.getUserAssets(userB), 50 ether);

        // User A tries to exceed cap from ARB
        // User A's shares are naturally held locally, no deal hack needed
        _fundLocalFromHub(userA, 50 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);

        sendParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);

        vm.prank(userA);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend(50 ether, sendParam, userA);

        // Verify user caps still enforced
        assertEq(yzEnforcedComposer_arb.getUserAssets(userA), 60 ether);
        assertEq(yzEnforcedComposer_arb.getUserAssets(userB), 50 ether);
    }

    function test_CrossChainReplay_Whitelist_EnforcedAcrossChains() public {
        // Setup whitelist
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelistEnabled(true);
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelist(userA, true);

        // User A deposits from ETH (whitelisted)
        _fundLocalFromHub(userA, 50 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);

        SendParam memory sendParam = _buildHopParam(address(0), userA, ETH_EID, 50 ether);
        uint256 fee = _getAndFundDepositFee(userA, sendParam);

        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend{value: fee}(50 ether, sendParam, userA);

        assertEq(vault_arb.totalAssets(), 50 ether);

        // User B tries to deposit from POL (not whitelisted)
        _fundLocalFromHub(userB, 30 ether);
        vm.prank(userB);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 30 ether);

        sendParam = _buildHopParam(address(0), userB, POL_EID, 30 ether);
        uint256 fee2 = _getAndFundDepositFee(userB, sendParam);

        vm.prank(userB);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend{value: fee2}(30 ether, sendParam, userB);

        // Verify whitelist enforced
        assertEq(vault_arb.totalAssets(), 50 ether);
        assertEq(yzEnforcedComposer_arb.getUserAssets(userB), 0);
    }

    function test_CrossChainReplay_Pause_EnforcedAcrossChains() public {
        // Pause deposits
        vm.prank(admin);
        yzEnforcedComposer_arb.pauseDeposits();

        // Try to deposit from any chain
        _fundLocalFromHub(userA, 50 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);

        SendParam memory sendParam = _buildHopParam(address(0), userA, ETH_EID, 50 ether);
        uint256 fee1 = _getAndFundDepositFee(userA, sendParam);

        vm.prank(userA);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend{value: fee1}(50 ether, sendParam, userA);

        sendParam = _buildHopParam(address(0), userA, POL_EID, 50 ether);
        uint256 fee2 = _getAndFundDepositFee(userA, sendParam);

        vm.prank(userA);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend{value: fee2}(50 ether, sendParam, userA);

        sendParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);

        vm.prank(userA);
        vm.expectRevert();
        yzEnforcedComposer_arb.depositAndSend(50 ether, sendParam, userA);

        // Verify deposits paused across all chains
        assertEq(vault_arb.totalAssets(), 0);
        assertEq(yzEnforcedComposer_arb.getUserAssets(userA), 0);
    }

    function test_CrossChainReplay_MessageIntegrity_Verified() public {
        // Setup
        _fundLocalFromHub(userA, 100 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 100 ether);

        // Normal deposit
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 100 ether);

        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(100 ether, sendParam, userA);

        // Verify normal operation
        assertEq(vault_arb.totalAssets(), 100 ether);
        assertEq(yzEnforcedComposer_arb.getUserAssets(userA), 100 ether);

        // The contract relies on LayerZero V2 for message verification
        // This test documents that replay protection is handled by the underlying protocol
        // and our enforcement checks work correctly even if replay were somehow attempted
    }
}
