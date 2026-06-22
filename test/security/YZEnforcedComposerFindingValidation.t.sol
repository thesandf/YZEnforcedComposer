// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {MessagingFee} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {OFTComposeMsgCodec} from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import {YZEnforcedComposer} from "../../src/YZEnforcedComposer.sol";
import "../unit/YZEnforcedComposerBase.t.sol";
import "forge-std/console2.sol";
import {stdError} from "forge-std/StdError.sol";
import {ILayerZeroEndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
import {IVaultComposerSync} from "@layerzerolabs/ovault-evm/contracts/interfaces/IVaultComposerSync.sol";

/*
 * Verification Summary Table:
 * ==============================================================================
 * Finding                                | Confirmed | Refuted | Inconclusive
 * ---------------------------------------|-----------|---------|---------------
 * 1. Pause Bypass (Cross-Chain)          |    Yes    |         |
 * 2. Whitelist Bypass (Cross-Chain)      |    Yes    |         |
 * 3. userShares Inflation                |    Yes    |         |
 * 4. canDeposit() Desynchronization      |    Yes    |         |
 * 5. Low-Decimal Asset Underflow         |    Yes    |         |
 * 6. Transfer Lockout (Design Tradeoff)  |    Yes    |         |
 * ==============================================================================
 */

// Helper mocks for Finding 5 (Low-Decimal Asset Underflow)
contract MockERC20WithDecimals is IERC20 {
    uint8 private _decimals;

    constructor(uint8 decimals_) {
        _decimals = decimals_;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function totalSupply() external pure returns (uint256) {
        return 0;
    }

    function balanceOf(address) external pure returns (uint256) {
        return 0;
    }

    function transfer(address, uint256) external pure returns (bool) {
        return true;
    }

    function allowance(address, address) external pure returns (uint256) {
        return 0;
    }

    function approve(address, uint256) external pure returns (bool) {
        return true;
    }

    function transferFrom(address, address, uint256) external pure returns (bool) {
        return true;
    }
}

contract MockOFTWithDecimals {
    uint8 private _decimals;
    address private _token;
    address private _endpoint;

    constructor(uint8 decimals_, address token_, address endpoint_) {
        _decimals = decimals_;
        _token = token_;
        _endpoint = endpoint_;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function token() external view returns (address) {
        return _token;
    }

    function approvalRequired() external pure returns (bool) {
        return false;
    }

    function endpoint() external view returns (address) {
        return _endpoint;
    }
}

contract MockShareOFTWithDecimals {
    address private _token;

    constructor(address token_) {
        _token = token_;
    }

    function token() external view returns (address) {
        return _token;
    }

    function approvalRequired() external pure returns (bool) {
        return true;
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }
}

contract MockVaultForLowDecimals is MockERC20WithDecimals {
    address public asset;

    constructor(address _asset) MockERC20WithDecimals(18) {
        asset = _asset;
    }

    function totalAssets() external pure returns (uint256) {
        return 0;
    }

    function convertToAssets(uint256) external pure returns (uint256) {
        return 0;
    }

    function redeem(uint256, address, address) external pure returns (uint256) {
        return 0;
    }
}

contract YZEnforcedComposerFindingValidation is YZEnforcedComposerBase {
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;

    function setUp() public override {
        super.setUp();
    }

    function getPacketNonce(bytes memory _packet) internal pure returns (uint64) {
        uint64 nonceVal;
        assembly {
            // _packet starts with 32 bytes of length.
            // The actual bytes start at _packet + 32.
            // Nonce starts at offset 1 from the start of the bytes, so _packet + 33.
            // We load 32 bytes from _packet + 33.
            // Since nonce is 8 bytes (uint64), it occupies the first 8 bytes of the 32 bytes loaded.
            // So we shift right by 192 bits (256 - 64) to get the uint64 value.
            nonceVal := shr(192, mload(add(_packet, 33)))
        }
        return nonceVal;
    }

    // =========================================================================
    // FINDING 1: Cross-Chain Pause Bypass (CONFIRMED)
    // =========================================================================

    function test_PauseBlocksLocalDeposit() external {
        // CONFIRMED: Local deposits are blocked by pause
        vm.prank(admin);
        yzEnforcedComposer_arb.pauseDeposits();

        _fundLocalFromHub(userA, 10 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 10 ether);
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 10 ether);

        vm.expectRevert(YZEnforcedComposer.YZ_DepositsPaused.selector);
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(10 ether, sendParam, userA);
    }

    function test_PauseBlocksCrossChainDeposit() external {
        // CONFIRMED: Cross-chain deposits are blocked by the pause
        vm.prank(admin);
        yzEnforcedComposer_arb.pauseDeposits();

        // Setup User A assets on ETH spoke chain
        deal(address(assetOFT_eth), userA, 10 ether);

        // Build return shares param for cross-chain send back
        SendParam memory sharesSendParam = SendParam({
            dstEid: ETH_EID,
            to: OFTComposeMsgCodec.addressToBytes32(userA),
            amountLD: 0, // overwritten by composer
            minAmountLD: 0,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });

        // Build spoke-to-hub sendParam with composeMsg
        bytes memory composeMsg = abi.encode(sharesSendParam, 0); // minMsgValue = 0
        SendParam memory sendParam = SendParam({
            dstEid: ARB_EID,
            to: OFTComposeMsgCodec.addressToBytes32(address(yzEnforcedComposer_arb)),
            amountLD: 10 ether,
            minAmountLD: 10 ether,
            extraOptions: OPTIONS_LZRECEIVE_500k,
            composeMsg: composeMsg,
            oftCmd: ""
        });

        // Get fees and send from spoke chain
        MessagingFee memory fee = assetOFT_eth.quoteSend(sendParam, false);
        deal(userA, fee.nativeFee + 1 ether);

        vm.prank(userA);
        assetOFT_eth.send{value: fee.nativeFee}(sendParam, fee, userA);

        // Retrieve the guid from the packets queue
        bytes32 dstAddress = OFTComposeMsgCodec.addressToBytes32(address(assetOFT_arb));
        bytes32 guid = packetsQueue[ARB_EID][dstAddress].back();
        uint64 packetNonce = getPacketNonce(packets[guid]);

        // Deliver the packets via endpoints (simulating lzReceive phase)
        verifyPackets(ARB_EID, address(assetOFT_arb));

        // Verify compose message is actually registered in the endpoint
        bytes memory expectedComposeMsg = OFTComposeMsgCodec.encode(
            packetNonce, // nonce
            ETH_EID, // srcEid
            10 ether, // amountLD
            abi.encodePacked(OFTComposeMsgCodec.addressToBytes32(userA), composeMsg)
        );
        bytes32 messageHash = ILayerZeroEndpointV2(endpoints[ARB_EID])
            .composeQueue(address(assetOFT_arb), address(yzEnforcedComposer_arb), guid, 0);
        assertEq(messageHash, keccak256(expectedComposeMsg), "Compose message not registered in endpoint");

        // Assert TVL before execution
        uint256 tvlBefore = vault_arb.totalAssets();
        uint256 trackedDepositsBefore = yzEnforcedComposer_arb.getUserShares(userA);
        assertEq(tvlBefore, 0);
        assertEq(trackedDepositsBefore, 0);

        // Expect Refunded event from parent
        vm.expectEmit(true, true, true, true, address(yzEnforcedComposer_arb));
        emit IVaultComposerSync.Refunded(guid);

        // Execute compose pranking the endpoint
        deal(address(endpoints[ARB_EID]), 10 ether);
        vm.prank(address(endpoints[ARB_EID]));
        yzEnforcedComposer_arb.lzCompose{value: 1 ether}(
            address(assetOFT_arb), guid, expectedComposeMsg, address(this), ""
        );

        // Assert that deposit was blocked and refunded (TVL and tracked deposits remain 0)
        uint256 tvlAfter = vault_arb.totalAssets();
        uint256 trackedDepositsAfter = yzEnforcedComposer_arb.getUserShares(userA);
        assertEq(tvlAfter, tvlBefore);
        assertEq(tvlAfter, 0);
        assertEq(trackedDepositsAfter, 0);
    }

    function test_PauseBlocksLocalRedeem() external {
        // CONFIRMED: Local redemptions are blocked by pause
        _fundLocalFromHub(userA, 10 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 10 ether);
        SendParam memory depParam = _buildHopParam(address(0), userA, ARB_EID, 10 ether);
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(10 ether, depParam, userA);

        vm.prank(admin);
        yzEnforcedComposer_arb.pauseRedemptions();

        vm.prank(userA);
        vault_arb.approve(address(yzEnforcedComposer_arb), 10 ether);

        SendParam memory redeemParam = _buildHopParam(address(0), userA, ARB_EID, 10 ether);

        vm.expectRevert(YZEnforcedComposer.YZ_RedemptionsPaused.selector);
        vm.prank(userA);
        yzEnforcedComposer_arb.redeemAndSend(10 ether, redeemParam, userA);
    }

    function test_PauseBlocksCrossChainRedeem() external {
        // CONFIRMED: Cross-chain redemptions are blocked by the pause
        // 1. Get shares to User A on ETH spoke chain
        _fundLocalFromHub(userA, 10 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 10 ether);
        SendParam memory depParam = _buildHopParam(address(0), userA, ARB_EID, 10 ether);
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(10 ether, depParam, userA);

        vm.prank(userA);
        vault_arb.approve(address(shareOFT_arb), 10 ether);
        SendParam memory bridgeParam = _buildHopParam(address(0), userA, ETH_EID, 10 ether);
        MessagingFee memory bridgeFee = shareOFT_arb.quoteSend(bridgeParam, false);
        deal(userA, bridgeFee.nativeFee + 1 ether);
        vm.prank(userA);
        shareOFT_arb.send{value: bridgeFee.nativeFee}(bridgeParam, bridgeFee, userA);

        verifyPackets(ETH_EID, address(shareOFT_eth));
        assertEq(shareOFT_eth.balanceOf(userA), 10 ether);

        // 2. Pause redemptions
        vm.prank(admin);
        yzEnforcedComposer_arb.pauseRedemptions();

        // 3. Initiate cross-chain redeem
        SendParam memory assetsSendParam = SendParam({
            dstEid: ETH_EID,
            to: OFTComposeMsgCodec.addressToBytes32(userA),
            amountLD: 0,
            minAmountLD: 0,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });
        bytes memory composeMsg = abi.encode(assetsSendParam, 0); // minMsgValue = 0
        SendParam memory sendParam = SendParam({
            dstEid: ARB_EID,
            to: OFTComposeMsgCodec.addressToBytes32(address(yzEnforcedComposer_arb)),
            amountLD: 10 ether,
            minAmountLD: 10 ether,
            extraOptions: OPTIONS_LZRECEIVE_500k,
            composeMsg: composeMsg,
            oftCmd: ""
        });

        MessagingFee memory fee = shareOFT_eth.quoteSend(sendParam, false);
        deal(userA, fee.nativeFee + 1 ether);
        vm.prank(userA);
        shareOFT_eth.send{value: fee.nativeFee}(sendParam, fee, userA);

        // Retrieve the guid
        bytes32 dstAddress = OFTComposeMsgCodec.addressToBytes32(address(shareOFT_arb));
        bytes32 guid = packetsQueue[ARB_EID][dstAddress].back();
        uint64 packetNonce = getPacketNonce(packets[guid]);

        // 4. Deliver packets to trigger compose on composer (lzReceive phase)
        verifyPackets(ARB_EID, address(shareOFT_arb));

        // Verify compose message is registered in the endpoint
        bytes memory expectedComposeMsg = OFTComposeMsgCodec.encode(
            packetNonce, // nonce
            ETH_EID, // srcEid
            10 ether, // amountLD
            abi.encodePacked(OFTComposeMsgCodec.addressToBytes32(userA), composeMsg)
        );
        bytes32 messageHash = ILayerZeroEndpointV2(endpoints[ARB_EID])
            .composeQueue(address(shareOFT_arb), address(yzEnforcedComposer_arb), guid, 0);
        assertEq(messageHash, keccak256(expectedComposeMsg), "Compose message not registered in endpoint");

        uint256 tvlBefore = vault_arb.totalAssets();
        uint256 trackedDepositsBefore = yzEnforcedComposer_arb.getUserShares(userA);
        assertEq(tvlBefore, 10 ether);
        assertEq(trackedDepositsBefore, 0);

        // Expect Refunded event from parent
        vm.expectEmit(true, true, true, true, address(yzEnforcedComposer_arb));
        emit IVaultComposerSync.Refunded(guid);

        // Execute compose pranking the endpoint
        deal(address(endpoints[ARB_EID]), 10 ether);
        vm.prank(address(endpoints[ARB_EID]));
        yzEnforcedComposer_arb.lzCompose{value: 1 ether}(
            address(shareOFT_arb), guid, expectedComposeMsg, address(this), ""
        );

        // Process the refund packets returning to ETH
        verifyPackets(ETH_EID, address(shareOFT_eth));

        // Assert that redemption was blocked and refunded (TVL and tracked deposits remain unchanged)
        uint256 tvlAfter = vault_arb.totalAssets();
        uint256 trackedDepositsAfter = yzEnforcedComposer_arb.getUserShares(userA);
        assertEq(tvlAfter, tvlBefore);
        assertEq(tvlAfter, 10 ether);
        assertEq(trackedDepositsAfter, 0);
        assertEq(shareOFT_eth.balanceOf(userA), 10 ether);
    }

    // =========================================================================
    // FINDING 2: Cross-Chain Whitelist Bypass (CONFIRMED)
    // =========================================================================

    function test_NonWhitelistedLocalDepositFails() external {
        // CONFIRMED: Local non-whitelisted deposits fail
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelistEnabled(true);

        _fundLocalFromHub(userA, 10 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 10 ether);
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 10 ether);

        vm.expectRevert(abi.encodeWithSelector(YZEnforcedComposer.YZ_NotWhitelisted.selector, userA));
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(10 ether, sendParam, userA);
    }

    function test_WhitelistBlocksCrossChainDeposit() external {
        // CONFIRMED: Cross-chain non-whitelisted deposits are blocked by whitelist
        vm.prank(admin);
        yzEnforcedComposer_arb.setWhitelistEnabled(true);

        // Setup User A assets on ETH spoke chain
        deal(address(assetOFT_eth), userA, 10 ether);

        // Build return shares param
        SendParam memory sharesSendParam = SendParam({
            dstEid: ETH_EID,
            to: OFTComposeMsgCodec.addressToBytes32(userA),
            amountLD: 0,
            minAmountLD: 0,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });
        bytes memory composeMsg = abi.encode(sharesSendParam, 0); // minMsgValue = 0

        // Build spoke-to-hub sendParam with compose message
        SendParam memory sendParam = SendParam({
            dstEid: ARB_EID,
            to: OFTComposeMsgCodec.addressToBytes32(address(yzEnforcedComposer_arb)),
            amountLD: 10 ether,
            minAmountLD: 10 ether,
            extraOptions: OPTIONS_LZRECEIVE_500k,
            composeMsg: composeMsg,
            oftCmd: ""
        });

        // Get fees and send
        MessagingFee memory fee = assetOFT_eth.quoteSend(sendParam, false);
        deal(userA, fee.nativeFee + 1 ether);

        vm.prank(userA);
        assetOFT_eth.send{value: fee.nativeFee}(sendParam, fee, userA);

        // Retrieve guid
        bytes32 dstAddress = OFTComposeMsgCodec.addressToBytes32(address(assetOFT_arb));
        bytes32 guid = packetsQueue[ARB_EID][dstAddress].back();
        uint64 packetNonce = getPacketNonce(packets[guid]);

        // Deliver packets
        verifyPackets(ARB_EID, address(assetOFT_arb));

        // Verify compose message is registered in the endpoint
        bytes memory expectedComposeMsg = OFTComposeMsgCodec.encode(
            packetNonce, // nonce
            ETH_EID, // srcEid
            10 ether, // amountLD
            abi.encodePacked(OFTComposeMsgCodec.addressToBytes32(userA), composeMsg)
        );
        bytes32 messageHash = ILayerZeroEndpointV2(endpoints[ARB_EID])
            .composeQueue(address(assetOFT_arb), address(yzEnforcedComposer_arb), guid, 0);
        assertEq(messageHash, keccak256(expectedComposeMsg), "Compose message not registered in endpoint");

        uint256 tvlBefore = vault_arb.totalAssets();
        uint256 trackedDepositsBefore = yzEnforcedComposer_arb.getUserShares(userA);
        assertEq(tvlBefore, 0);
        assertEq(trackedDepositsBefore, 0);

        // Expect Refunded event from parent
        vm.expectEmit(true, true, true, true, address(yzEnforcedComposer_arb));
        emit IVaultComposerSync.Refunded(guid);

        // Execute compose pranking the endpoint
        deal(address(endpoints[ARB_EID]), 10 ether);
        vm.prank(address(endpoints[ARB_EID]));
        yzEnforcedComposer_arb.lzCompose{value: 1 ether}(
            address(assetOFT_arb), guid, expectedComposeMsg, address(this), ""
        );

        // Assert that deposit was blocked and refunded (TVL remains 0)
        uint256 tvlAfter = vault_arb.totalAssets();
        uint256 trackedDepositsAfter = yzEnforcedComposer_arb.getUserShares(userA);
        assertEq(tvlAfter, tvlBefore);
        assertEq(tvlAfter, 0);
        assertEq(trackedDepositsAfter, 0);
    }

    // =========================================================================
    // FINDING 3: userShares Inflation (CONFIRMED)
    // =========================================================================

    function test_UserSharesTrackingMatchesActualMintedShares() external {
        // CONFIRMED: userShares mapping gets inflated on deposit
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(userA, 100 ether);

        // Setup initial deposit from another user so tvlBefore > 0 and total supply > 0
        _fundLocalFromHub(userB, 10 ether);
        vm.prank(userB);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 10 ether);
        SendParam memory paramB = _buildHopParam(address(0), userB, ARB_EID, 10 ether);
        vm.prank(userB);
        yzEnforcedComposer_arb.depositAndSend(10 ether, paramB, userB);

        // User A deposits
        uint256 depositAmount = 5 ether;
        _fundLocalFromHub(userA, depositAmount);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), depositAmount);

        uint256 tvlBefore = vault_arb.totalAssets();
        uint256 supplyBefore = vault_arb.totalSupply();

        // Query ERC4626 previewDeposit before deposit
        uint256 expectedShares = vault_arb.previewDeposit(depositAmount);

        SendParam memory paramA = _buildHopParam(address(0), userA, ARB_EID, depositAmount);

        uint256 shareBalanceBefore = vault_arb.balanceOf(userA);
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(depositAmount, paramA, userA);
        uint256 shareBalanceAfter = vault_arb.balanceOf(userA);
        uint256 actualSharesMinted = shareBalanceAfter - shareBalanceBefore;

        // Internal tracked shares:
        uint256 trackedShares = yzEnforcedComposer_arb.userShares(userA);

        console2.log("--- userShares Inflation Debug ---");
        console2.log("tvlBefore:", tvlBefore);
        console2.log("supplyBefore:", supplyBefore);
        console2.log("depositAmount:", depositAmount);
        console2.log("expectedShares:", expectedShares);
        console2.log("trackedShares in mapping:", trackedShares);
        console2.log("actualSharesMinted in vault:", actualSharesMinted);

        // Assert that the inflation bug is fixed and internal shares mapping matches actual vault shares minted
        assertEq(trackedShares, actualSharesMinted, "trackedShares does not match actualSharesMinted");
        assertEq(trackedShares, expectedShares, "trackedShares does not match expectedShares");
    }

    // =========================================================================
    // FINDING 4: canDeposit() Desynchronization (CONFIRMED)
    // =========================================================================

    function test_CanDepositMatchesActualExecution() external {
        // CONFIRMED: canDeposit returns true but execution reverts
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(userA, 20 ether);

        _fundLocalFromHub(userA, 10 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 10 ether);
        SendParam memory depParam = _buildHopParam(address(0), userA, ARB_EID, 10 ether);
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(10 ether, depParam, userA);

        // Simulate yield growth by dealing assets directly to the vault
        deal(address(assetOFT_arb), address(vault_arb), 15 ether);

        // checks user cap: convertToAssets(10 + 5.33) = 23 > 20. Returns false.
        (bool allowed, string memory reason) = yzEnforcedComposer_arb.canDeposit(userA, 8 ether);
        assertFalse(allowed, "canDeposit should return false since user cap would be exceeded");
        assertEq(reason, "User cap exceeded");

        // Attempt actual deposit.
        // expectedShares = 8 * 10 / 15 = 5.33 ether.
        // totalShares = 10 + 5.33 = 15.33 ether.
        // convertToAssets(15.33) = 23 ether > 20 ether cap. Reverts!
        _fundLocalFromHub(userA, 8 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 8 ether);

        SendParam memory depParam2 = _buildHopParam(address(0), userA, ARB_EID, 8 ether);

        // Expect exact revert selector
        vm.expectRevert(
            abi.encodeWithSelector(
                YZEnforcedComposer.YZ_UserCapExceeded.selector,
                userA,
                14999999999999999999, // 15 ether (minus 1 wei rounding)
                8000000000000000000, // 8 ether
                20000000000000000000 // 20 ether
            )
        );
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(8 ether, depParam2, userA);
    }

    // =========================================================================
    // FINDING 5: Low-Decimal Asset Underflow (CONFIRMED)
    // =========================================================================

    function test_RedeemWithFiveDecimalAssetDoesNotPanic() external {
        // CONFIRMED: Redeeming with low-decimal asset (< 6 decimals) does not underflow anymore and succeeds
        MockERC20WithDecimals mockAsset = new MockERC20WithDecimals(5);
        MockOFTWithDecimals mockOft = new MockOFTWithDecimals(18, address(mockAsset), address(endpoints[ARB_EID]));
        MockVaultForLowDecimals mockVault = new MockVaultForLowDecimals(address(mockAsset));
        MockShareOFTWithDecimals mockShareOft = new MockShareOFTWithDecimals(address(mockVault));

        YZEnforcedComposer testComposer =
            new YZEnforcedComposer(address(mockVault), address(mockOft), address(mockShareOft), admin);

        SendParam memory redeemParam = _buildHopParam(address(0), userA, ARB_EID, 10 ether);

        // Executes successfully because 5 decimals is handled safely (conversion rate is set to 1)
        testComposer.redeemAndSend(10 ether, redeemParam, address(this));
    }

    function test_RedeemWithSixDecimalAssetDoesNotPanic() external {
        // CONFIRMED: Redeeming with >= 6 decimal asset does not underflow (decimals() - 6 >= 0) and succeeds
        MockERC20WithDecimals mockAsset = new MockERC20WithDecimals(6);
        MockOFTWithDecimals mockOft = new MockOFTWithDecimals(18, address(mockAsset), address(endpoints[ARB_EID]));
        MockVaultForLowDecimals mockVault = new MockVaultForLowDecimals(address(mockAsset));
        MockShareOFTWithDecimals mockShareOft = new MockShareOFTWithDecimals(address(mockVault));

        YZEnforcedComposer testComposer =
            new YZEnforcedComposer(address(mockVault), address(mockOft), address(mockShareOft), admin);

        SendParam memory redeemParam = _buildHopParam(address(0), userA, ARB_EID, 0);

        // Executes successfully because 6 - 6 = 0 does not underflow
        testComposer.redeemAndSend(0, redeemParam, address(this));
    }

    // =========================================================================
    // FINDING 6: Transfer Lockout (Design Tradeoff) (CONFIRMED)
    // =========================================================================

    function test_DepositCapAccountingIgnoresShareTransfers() external {
        // Under the Maximum Ownership Cap model, transferring shares frees up the user's cap
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(userA, 50 ether);

        _fundLocalFromHub(userA, 30 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 30 ether);
        SendParam memory depParam = _buildHopParam(address(0), userA, ARB_EID, 30 ether);
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(30 ether, depParam, userA);

        assertEq(yzEnforcedComposer_arb.getUserShares(userA), 30 ether);

        // User A transfers all vault shares to User B
        uint256 userAShareBalance = vault_arb.balanceOf(userA);
        vm.prank(userA);
        vault_arb.transfer(userB, userAShareBalance);

        assertEq(vault_arb.balanceOf(userA), 0);

        // Under the new model, User A's cap is successfully freed (ownership = 0)
        assertEq(yzEnforcedComposer_arb.getUserShares(userA), 0, "Cap was not freed!");
    }
}
