// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import "forge-std/Test.sol";
import "./YieldZeroBaseTest.t.sol";

contract YieldZeroFlowTest is YieldZeroBaseTest {
    uint256 constant MIN_RETURN_GAS = 0.01 ether;
    uint256 constant EXTRA_GAS_BUFFER = 0.1 ether;

    function setUp() public virtual override {
        super.setUp();
    }

    // Helper Functions

    function _addressToBytes32(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    function _buildHopParam(address recipient, address composer, uint32 _dstEid)
        internal
        pure
        returns (SendParam memory)
    {
        if (recipient == address(0)) {
            recipient = composer;
        }
        return SendParam({
            dstEid: _dstEid,
            to: _addressToBytes32(recipient),
            amountLD: TOKENS_TO_SEND,
            minAmountLD: (TOKENS_TO_SEND * 99) / 100,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });
    }

    function _buildDepositParam(address composer) internal view returns (SendParam memory) {
        return SendParam({
            dstEid: ARB_EID,
            to: _addressToBytes32(composer),
            amountLD: TOKENS_TO_SEND,
            minAmountLD: (TOKENS_TO_SEND * 99) / 100,
            extraOptions: OPTIONS_LZRECEIVE_500k,
            composeMsg: "",
            oftCmd: ""
        });
    }

    // Tests

    function test_localDepositAndRedeemFlow() public {
        // Mint and approve on Arbitrum
        _fundLocalFromHub(userA, TOKENS_TO_SEND);
        vm.prank(userA);
        assetOFT_arb.approve(address(yieldZeroComposer_arb), TOKENS_TO_SEND);
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID);

        uint256 expectedShares = vault_arb.previewDeposit(TOKENS_TO_SEND);

        vm.prank(userA);
        yieldZeroComposer_arb.initiateDepositAndSend(TOKENS_TO_SEND, expectedShares, sendParam, userA);

        assertEq(vault_arb.totalAssets(), TOKENS_TO_SEND, "Vault should hold deposited assets");
        assertEq(vault_arb.balanceOf(userA), expectedShares, "User should receive vault shares");

        // Redeem
        vm.prank(userA);

        vault_arb.approve(address(yieldZeroComposer_arb), expectedShares);

        uint256 expectedAssets = vault_arb.previewRedeem(expectedShares);

        vm.prank(userA);
        yieldZeroComposer_arb.initiateRedeemAndSend(expectedShares, expectedAssets, sendParam, userA);

        assertEq(vault_arb.totalAssets(), 0, "Vault should have no assets after redeem");
        assertEq(assetOFT_arb.balanceOf(userA), TOKENS_TO_SEND, "User should receive assets back");
    }

    function test_crossChainDepositEthToArbVaultBackToEth() public {
        // Mint & approve on Ethereum
        _fundFromHub(userA, TOKENS_TO_SEND, ETH_EID);
        vm.prank(userA);
        assetOFT_eth.approve(address(assetOFT_eth), TOKENS_TO_SEND);

        // Prepare hop parameters (return leg: shares → userA on ETH)
        SendParam memory hopParam = _buildHopParam(userA, address(yieldZeroComposer_arb), ETH_EID);

        // Minimum native token needed for the return send
        bytes memory composePayload = abi.encode(hopParam, MIN_RETURN_GAS);

        // Main cross-chain deposit: ETH → Arbitrum composer
        SendParam memory sendParam = _buildDepositParam(address(yieldZeroComposer_arb));
        sendParam.composeMsg = composePayload;

        MessagingFee memory fee = assetOFT_eth.quoteSend(sendParam, false);
        deal(userA, fee.nativeFee + 1 ether);

        vm.prank(userA);
        (MessagingReceipt memory receipt,) = assetOFT_eth.send{value: fee.nativeFee}(sendParam, fee, userA);

        // Fund endpoint for compose execution
        deal(address(endpoints[ARB_EID]), 1 ether);

        // Simulate LayerZero delivery → lzReceive → sendCompose
        verifyPackets(ARB_EID, _addressToBytes32(address(assetOFT_arb)));

        // Reconstruct wrapped compose message (as LZ endpoint does)
        bytes32 sourceOft = _addressToBytes32(address(assetOFT_eth));

        bytes memory wrappedMsg = abi.encodePacked(
            uint64(receipt.nonce),
            uint32(ETH_EID),
            TOKENS_TO_SEND,
            sourceOft, // sender (source OFT)
            composePayload // original compose message
        );

        // Execute lzCompose (prank from LZ endpoint)
        vm.prank(address(endpoints[ARB_EID]));
        yieldZeroComposer_arb.lzCompose{value: MIN_RETURN_GAS + EXTRA_GAS_BUFFER}(
            address(assetOFT_arb),
            receipt.guid,
            wrappedMsg,
            address(0), // executor
            "" // extraData
        );

        // Verify vault state after deposit
        assertEq(vault_arb.totalAssets(), TOKENS_TO_SEND, "Vault should hold the deposited assets");

        // Deliver return leg (shares → Ethereum to userA)
        verifyPackets(ETH_EID, _addressToBytes32(address(shareOFT_eth)));

        // Final assertion: user received shares on Ethereum
        assertEq(
            shareOFT_eth.balanceOf(userA),
            TOKENS_TO_SEND,
            "User should receive vault shares on Ethereum after round-trip"
        );
    }

    function test_crossChainRedeemArbVaultToEthBackToArb() public {
        // Setup: deposit into Arbitrum vault
        _fundLocalFromHub(userA, TOKENS_TO_SEND);
        vm.prank(userA);
        assetOFT_arb.approve(address(yieldZeroComposer_arb), TOKENS_TO_SEND);

        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID);
        uint256 expectedShares = vault_arb.previewDeposit(TOKENS_TO_SEND);

        vm.prank(userA);
        yieldZeroComposer_arb.initiateDepositAndSend(TOKENS_TO_SEND, expectedShares, sendParam, userA);

        // Prepare hop parameters (return leg: assets → userA on ARB)
        SendParam memory hopParam = _buildHopParam(userA, address(yieldZeroComposer_arb), ARB_EID);

        bytes memory composePayload = abi.encode(hopParam, MIN_RETURN_GAS);

        SendParam memory redeemParam = SendParam({
            dstEid: ETH_EID,
            to: _addressToBytes32(address(yieldZeroComposer_arb)),
            amountLD: expectedShares,
            minAmountLD: (expectedShares * 99) / 100,
            extraOptions: OPTIONS_LZRECEIVE_500k,
            composeMsg: composePayload,
            oftCmd: ""
        });

        vm.prank(userA);
        vault_arb.approve(address(shareOFT_arb), expectedShares);
        MessagingFee memory fee = shareOFT_arb.quoteSend(redeemParam, false);
        deal(userA, fee.nativeFee + 1 ether);

        vm.prank(userA);
        (MessagingReceipt memory receipt,) = shareOFT_arb.send{value: fee.nativeFee}(redeemParam, fee, userA);

        deal(address(endpoints[ETH_EID]), 1 ether);

        // Simulate LayerZero delivery → lzReceive → sendCompose
        verifyPackets(ETH_EID, _addressToBytes32(address(shareOFT_eth)));

        // Ensure the composer holds the shares before redeeming: transfer from the adapter
        vm.prank(address(shareOFT_arb));
        vault_arb.transfer(address(yieldZeroComposer_arb), expectedShares);

        bytes32 sourceOft = _addressToBytes32(address(shareOFT_arb));
        bytes memory wrappedMsg = abi.encodePacked(
            uint64(receipt.nonce),
            uint32(ARB_EID),
            expectedShares,
            sourceOft,
            composePayload // original compose message
        );

        // Fund endpoint for compose execution
        deal(address(endpoints[ARB_EID]), 2 ether);
        
        vm.prank(address(endpoints[ARB_EID]));
        yieldZeroComposer_arb.lzCompose{value: 1 ether}(
            address(shareOFT_arb),
            receipt.guid,
            wrappedMsg,
            address(0), // executor
            "" // extraData
        );

        // Deliver return leg (assets → Arbitrum to userA)
        verifyPackets(ARB_EID, _addressToBytes32(address(assetOFT_arb)));
        assertEq(
            assetOFT_arb.balanceOf(userA), TOKENS_TO_SEND, "User should receive assets on Arbitrum after round-trip"
        );
    }

    function test_crossChainDepositArbToEthReceiveShares() public {
        _fundLocalFromHub(userA, TOKENS_TO_SEND);
        vm.prank(userA);
        assetOFT_arb.approve(address(yieldZeroComposer_arb), TOKENS_TO_SEND);

        SendParam memory hopParam = _buildHopParam(userA, address(0), ETH_EID);

        bytes memory composePayload = abi.encode(hopParam, MIN_RETURN_GAS);

        SendParam memory sendParam = _buildHopParam(address(userA), address(0), ETH_EID);
        sendParam.composeMsg = composePayload;
        sendParam.extraOptions = OPTIONS_LZRECEIVE_500k;

        MessagingFee memory fee = shareOFT_arb.quoteSend(sendParam, false);

        deal(userA, fee.nativeFee + 0.1 ether);

        uint256 expectedShares = vault_arb.previewDeposit(TOKENS_TO_SEND);
        vm.prank(userA);
        yieldZeroComposer_arb.initiateDepositAndSend{value: fee.nativeFee}(
            TOKENS_TO_SEND, expectedShares, sendParam, userA
        );

        deal(address(endpoints[ETH_EID]), 1 ether);
        verifyPackets(ETH_EID, _addressToBytes32(address(shareOFT_eth)));

        assertEq(shareOFT_eth.balanceOf(userA), TOKENS_TO_SEND, "User should receive shares on ETH");
    }

    function test_crossChainDepositEthToArbReceiveShares() public {
        _fundFromHub(userA, TOKENS_TO_SEND, ETH_EID);

        SendParam memory hopParam = _buildHopParam(userA, address(0), ARB_EID);

        bytes memory composePayload = abi.encode(hopParam, MIN_RETURN_GAS);

        SendParam memory sendParam = _buildDepositParam(address(yieldZeroComposer_arb));
        sendParam.composeMsg = composePayload;

        MessagingFee memory fee = assetOFT_eth.quoteSend(sendParam, false);
        deal(userA, fee.nativeFee + 1 ether);

        vm.prank(userA);
        (MessagingReceipt memory receipt,) = assetOFT_eth.send{value: fee.nativeFee}(sendParam, fee, userA);

        deal(address(endpoints[ARB_EID]), 1 ether);

        verifyPackets(ARB_EID, _addressToBytes32(address(assetOFT_arb)));

        bytes32 sourceOft = _addressToBytes32(address(assetOFT_eth));
        bytes memory wrappedMsg =
            abi.encodePacked(uint64(receipt.nonce), uint32(ETH_EID), TOKENS_TO_SEND, sourceOft, composePayload);

        vm.prank(address(endpoints[ARB_EID]));
        yieldZeroComposer_arb.lzCompose{value: MIN_RETURN_GAS + EXTRA_GAS_BUFFER}(
            address(assetOFT_arb), receipt.guid, wrappedMsg, address(0), ""
        );

        verifyPackets(ARB_EID, _addressToBytes32(address(shareOFT_arb)));

        assertEq(vault_arb.balanceOf(userA), TOKENS_TO_SEND, "User should receive shares on ARB");
    }

    function test_crossChainDepositPolToArbVaultBackToPol() public {
        // Mint & approve on Polygon
        _fundFromHub(userA, TOKENS_TO_SEND, POL_EID);
        vm.prank(userA);
        assetOFT_pol.approve(address(assetOFT_pol), TOKENS_TO_SEND);

        // Prepare hop parameters (return leg: shares → userA on POL)
        SendParam memory hopParam = _buildHopParam(userA, address(yieldZeroComposer_arb), POL_EID);

        bytes memory composePayload = abi.encode(hopParam, MIN_RETURN_GAS);

        // Main cross-chain deposit: POL → Arbitrum composer
        SendParam memory sendParam = _buildDepositParam(address(yieldZeroComposer_arb));
        sendParam.composeMsg = composePayload;

        MessagingFee memory fee = assetOFT_pol.quoteSend(sendParam, false);
        deal(userA, fee.nativeFee + 1 ether);

        vm.prank(userA);
        (MessagingReceipt memory receipt,) = assetOFT_pol.send{value: fee.nativeFee}(sendParam, fee, userA);

        deal(address(endpoints[ARB_EID]), 1 ether);

        // Simulate delivery to ARB AssetOFT
        verifyPackets(ARB_EID, _addressToBytes32(address(assetOFT_arb)));

        bytes32 sourceOft = _addressToBytes32(address(assetOFT_pol));
        bytes memory wrappedMsg =
            abi.encodePacked(uint64(receipt.nonce), uint32(POL_EID), TOKENS_TO_SEND, sourceOft, composePayload);

        // Execute lzCompose on ARB
        vm.prank(address(endpoints[ARB_EID]));
        yieldZeroComposer_arb.lzCompose{value: MIN_RETURN_GAS + EXTRA_GAS_BUFFER}(
            address(assetOFT_arb), receipt.guid, wrappedMsg, address(0), ""
        );

        // Deliver return leg (shares → POL to userA)
        verifyPackets(POL_EID, _addressToBytes32(address(shareOFT_pol)));

        assertEq(shareOFT_pol.balanceOf(userA), TOKENS_TO_SEND, "User should receive vault shares on Polygon");
        assertEq(vault_arb.totalAssets(), TOKENS_TO_SEND, "Vault should hold assets");
    }

    function test_crossChainDepositEthToArbVaultBackToPol() public {
        // Mint & approve on ETH
        _fundFromHub(userA, TOKENS_TO_SEND, ETH_EID);
        vm.prank(userA);
        assetOFT_eth.approve(address(assetOFT_eth), TOKENS_TO_SEND);

        // Prepare hop parameters (return leg: shares → userA on POL)
        SendParam memory hopParam = _buildHopParam(userA, address(yieldZeroComposer_arb), POL_EID);

        bytes memory composePayload = abi.encode(hopParam, MIN_RETURN_GAS);

        SendParam memory sendParam = _buildDepositParam(address(yieldZeroComposer_arb));
        sendParam.composeMsg = composePayload;

        MessagingFee memory fee = assetOFT_eth.quoteSend(sendParam, false);
        deal(userA, fee.nativeFee + 1 ether);

        vm.prank(userA);
        (MessagingReceipt memory receipt,) = assetOFT_eth.send{value: fee.nativeFee}(sendParam, fee, userA);

        deal(address(endpoints[ARB_EID]), 1 ether);
        verifyPackets(ARB_EID, _addressToBytes32(address(assetOFT_arb)));

        bytes32 sourceOft = _addressToBytes32(address(assetOFT_eth));
        bytes memory wrappedMsg =
            abi.encodePacked(uint64(receipt.nonce), uint32(ETH_EID), TOKENS_TO_SEND, sourceOft, composePayload);

        vm.prank(address(endpoints[ARB_EID]));
        yieldZeroComposer_arb.lzCompose{value: MIN_RETURN_GAS + EXTRA_GAS_BUFFER}(
            address(assetOFT_arb), receipt.guid, wrappedMsg, address(0), ""
        );

        // Deliver return leg (shares → POL to userA)
        verifyPackets(POL_EID, _addressToBytes32(address(shareOFT_pol)));

        assertEq(
            shareOFT_pol.balanceOf(userA), TOKENS_TO_SEND, "User should receive shares on Polygon from ETH deposit"
        );
    }

    function test_crossChainRedeemPolToArbVaultBackToEth() public {
        // Setup: user has shares on Polygon
        _fundLocalFromHub(address(yieldZeroComposer_arb), TOKENS_TO_SEND);
        vm.prank(address(yieldZeroComposer_arb));
        vault_arb.deposit(TOKENS_TO_SEND, address(yieldZeroComposer_arb));

        // Transfer shares to POL
        SendParam memory sendToPol = _buildHopParam(userA, address(yieldZeroComposer_arb), POL_EID);
        MessagingFee memory feePol = shareOFT_arb.quoteSend(sendToPol, false);
        deal(address(yieldZeroComposer_arb), feePol.nativeFee);
        vm.prank(address(yieldZeroComposer_arb));
        shareOFT_arb.send{value: feePol.nativeFee}(sendToPol, feePol, address(yieldZeroComposer_arb));
        verifyPackets(POL_EID, _addressToBytes32(address(shareOFT_pol)));

        assertEq(shareOFT_pol.balanceOf(userA), TOKENS_TO_SEND);

        // Prepare redemption: Shares from POL -> ARB Redeem -> ETH Assets
        SendParam memory hopParam = _buildHopParam(userA, address(yieldZeroComposer_arb), ETH_EID);
        bytes memory composePayload = abi.encode(hopParam, MIN_RETURN_GAS);

        SendParam memory redeemParam = SendParam({
            dstEid: ARB_EID,
            to: _addressToBytes32(address(yieldZeroComposer_arb)),
            amountLD: TOKENS_TO_SEND,
            minAmountLD: (TOKENS_TO_SEND * 99) / 100,
            extraOptions: OPTIONS_LZRECEIVE_500k,
            composeMsg: composePayload,
            oftCmd: ""
        });

        vm.prank(userA);
        shareOFT_pol.approve(address(shareOFT_pol), TOKENS_TO_SEND);
        MessagingFee memory feeRedeem = shareOFT_pol.quoteSend(redeemParam, false);
        deal(userA, feeRedeem.nativeFee + 1 ether);

        vm.prank(userA);
        (MessagingReceipt memory receipt,) =
            shareOFT_pol.send{value: feeRedeem.nativeFee}(redeemParam, feeRedeem, userA);

        deal(address(endpoints[ARB_EID]), 1 ether);
        verifyPackets(ARB_EID, _addressToBytes32(address(shareOFT_arb)));

        // Note: lzReceive on shareOFT_arb already transferred shares to yieldZeroComposer_arb

        bytes32 sourceOft = _addressToBytes32(address(shareOFT_pol));
        bytes memory wrappedMsg =
            abi.encodePacked(uint64(receipt.nonce), uint32(POL_EID), TOKENS_TO_SEND, sourceOft, composePayload);

        vm.prank(address(endpoints[ARB_EID]));
        yieldZeroComposer_arb.lzCompose{value: MIN_RETURN_GAS + EXTRA_GAS_BUFFER}(
            address(shareOFT_arb), receipt.guid, wrappedMsg, address(0), ""
        );

        // Deliver return leg (assets → ETH to userA)
        verifyPackets(ETH_EID, _addressToBytes32(address(assetOFT_eth)));

        assertEq(
            assetOFT_eth.balanceOf(userA),
            TOKENS_TO_SEND,
            "User should receive assets on ETH from POL shares redemption"
        );
    }

    // Multi-hop & Complex Flow Tests

    function test_largeAmountOperations() public {
        uint256 largeAmount = 100 ether; // 100x the normal amount

        // Mint large amount
        _fundLocalFromHub(userA, largeAmount);
        vm.prank(userA);
        assetOFT_arb.approve(address(yieldZeroComposer_arb), largeAmount);

        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID);

        // Test large deposit
        uint256 expectedSharesLarge = vault_arb.previewDeposit(largeAmount);
        vm.prank(userA);
        yieldZeroComposer_arb.initiateDepositAndSend(largeAmount, expectedSharesLarge, sendParam, userA);

        assertEq(vault_arb.totalAssets(), largeAmount);
        assertEq(vault_arb.balanceOf(userA), expectedSharesLarge);

        // Test large redeem
        vm.prank(userA);
        vault_arb.approve(address(yieldZeroComposer_arb), expectedSharesLarge);

        uint256 expectedAssetsLarge = vault_arb.previewRedeem(expectedSharesLarge);
        vm.prank(userA);
        yieldZeroComposer_arb.initiateRedeemAndSend(expectedSharesLarge, expectedAssetsLarge, sendParam, userA);

        assertEq(vault_arb.totalAssets(), 0);
        assertEq(assetOFT_arb.balanceOf(userA), largeAmount);
    }

    // New Tests for Feedback Scenarios

    function test_depositFromSpokeReceiveOnSameSpoke() public {
        // Deposit from Arbitrum (spoke) and receive shares on Arbitrum (same spoke)
        _fundLocalFromHub(userA, TOKENS_TO_SEND);
        vm.prank(userA);
        assetOFT_arb.approve(address(yieldZeroComposer_arb), TOKENS_TO_SEND);

        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID);
        uint256 expectedShares = vault_arb.previewDeposit(TOKENS_TO_SEND);

        vm.prank(userA);
        yieldZeroComposer_arb.initiateDepositAndSend(TOKENS_TO_SEND, expectedShares, sendParam, userA);

        assertEq(vault_arb.totalAssets(), TOKENS_TO_SEND);
        assertEq(vault_arb.balanceOf(userA), expectedShares);
    }

    function test_depositFromSpokeReceiveOnDifferentSpoke() public {
        // Deposit from Ethereum (spoke) and receive shares on Polygon (different spoke)
        _fundFromHub(userA, TOKENS_TO_SEND, ETH_EID);
        vm.prank(userA);
        assetOFT_eth.approve(address(assetOFT_eth), TOKENS_TO_SEND);

        // Return shares to Polygon instead of Ethereum
        SendParam memory hopParam = _buildHopParam(userA, address(yieldZeroComposer_arb), POL_EID);
        bytes memory composePayload = abi.encode(hopParam, MIN_RETURN_GAS);

        SendParam memory sendParam = _buildDepositParam(address(yieldZeroComposer_arb));
        sendParam.composeMsg = composePayload;

        MessagingFee memory fee = assetOFT_eth.quoteSend(sendParam, false);
        deal(userA, fee.nativeFee + 1 ether);

        vm.prank(userA);
        (MessagingReceipt memory receipt,) = assetOFT_eth.send{value: fee.nativeFee}(sendParam, fee, userA);

        deal(address(endpoints[ARB_EID]), 1 ether);
        verifyPackets(ARB_EID, _addressToBytes32(address(assetOFT_arb)));

        bytes32 sourceOft = _addressToBytes32(address(assetOFT_eth));
        bytes memory wrappedMsg =
            abi.encodePacked(uint64(receipt.nonce), uint32(ETH_EID), TOKENS_TO_SEND, sourceOft, composePayload);

        vm.prank(address(endpoints[ARB_EID]));
        yieldZeroComposer_arb.lzCompose{value: MIN_RETURN_GAS + EXTRA_GAS_BUFFER}(
            address(assetOFT_arb), receipt.guid, wrappedMsg, address(0), ""
        );

        verifyPackets(POL_EID, _addressToBytes32(address(shareOFT_pol)));
        assertEq(shareOFT_pol.balanceOf(userA), TOKENS_TO_SEND);
    }

    function test_depositFromSpokeReceiveOnHub() public {
        // Deposit from Polygon (spoke) and receive shares on Arbitrum (hub)
        _fundFromHub(userA, TOKENS_TO_SEND, POL_EID);
        vm.prank(userA);
        assetOFT_pol.approve(address(assetOFT_pol), TOKENS_TO_SEND);

        // Return shares to Arbitrum (hub) instead of Polygon
        SendParam memory hopParam = _buildHopParam(userA, address(yieldZeroComposer_arb), ARB_EID);
        bytes memory composePayload = abi.encode(hopParam, MIN_RETURN_GAS);

        SendParam memory sendParam = _buildDepositParam(address(yieldZeroComposer_arb));
        sendParam.composeMsg = composePayload;

        MessagingFee memory fee = assetOFT_pol.quoteSend(sendParam, false);
        deal(userA, fee.nativeFee + 1 ether);

        vm.prank(userA);
        (MessagingReceipt memory receipt,) = assetOFT_pol.send{value: fee.nativeFee}(sendParam, fee, userA);

        deal(address(endpoints[ARB_EID]), 1 ether);
        verifyPackets(ARB_EID, _addressToBytes32(address(assetOFT_arb)));

        bytes32 sourceOft = _addressToBytes32(address(assetOFT_pol));
        bytes memory wrappedMsg =
            abi.encodePacked(uint64(receipt.nonce), uint32(POL_EID), TOKENS_TO_SEND, sourceOft, composePayload);

        vm.prank(address(endpoints[ARB_EID]));
        yieldZeroComposer_arb.lzCompose{value: MIN_RETURN_GAS + EXTRA_GAS_BUFFER}(
            address(assetOFT_arb), receipt.guid, wrappedMsg, address(0), ""
        );

        verifyPackets(ARB_EID, _addressToBytes32(address(shareOFT_arb)));
        assertEq(vault_arb.balanceOf(userA), TOKENS_TO_SEND);
    }

    function test_redeemFromSpokeReceiveOnDifferentSpoke() public {
        // Deposit first to get shares on Polygon
        _fundLocalFromHub(address(yieldZeroComposer_arb), TOKENS_TO_SEND);
        vm.prank(address(yieldZeroComposer_arb));
        vault_arb.deposit(TOKENS_TO_SEND, address(yieldZeroComposer_arb));

        SendParam memory sendToPol = _buildHopParam(userA, address(yieldZeroComposer_arb), POL_EID);
        MessagingFee memory feePol = shareOFT_arb.quoteSend(sendToPol, false);
        deal(address(yieldZeroComposer_arb), feePol.nativeFee);
        vm.prank(address(yieldZeroComposer_arb));
        shareOFT_arb.send{value: feePol.nativeFee}(sendToPol, feePol, address(yieldZeroComposer_arb));
        verifyPackets(POL_EID, _addressToBytes32(address(shareOFT_pol)));

        // Redeem from Polygon (spoke) and receive assets on Ethereum (different spoke)
        SendParam memory hopParam = _buildHopParam(userA, address(yieldZeroComposer_arb), ETH_EID);
        bytes memory composePayload = abi.encode(hopParam, MIN_RETURN_GAS);

        SendParam memory redeemParam = SendParam({
            dstEid: ARB_EID,
            to: _addressToBytes32(address(yieldZeroComposer_arb)),
            amountLD: TOKENS_TO_SEND,
            minAmountLD: (TOKENS_TO_SEND * 99) / 100,
            extraOptions: OPTIONS_LZRECEIVE_500k,
            composeMsg: composePayload,
            oftCmd: ""
        });

        vm.prank(userA);
        shareOFT_pol.approve(address(shareOFT_pol), TOKENS_TO_SEND);
        MessagingFee memory feeRedeem = shareOFT_pol.quoteSend(redeemParam, false);
        deal(userA, feeRedeem.nativeFee + 1 ether);

        vm.prank(userA);
        (MessagingReceipt memory receipt,) =
            shareOFT_pol.send{value: feeRedeem.nativeFee}(redeemParam, feeRedeem, userA);

        deal(address(endpoints[ARB_EID]), 1 ether);
        verifyPackets(ARB_EID, _addressToBytes32(address(shareOFT_arb)));

        bytes32 sourceOft = _addressToBytes32(address(shareOFT_pol));
        bytes memory wrappedMsg =
            abi.encodePacked(uint64(receipt.nonce), uint32(POL_EID), TOKENS_TO_SEND, sourceOft, composePayload);

        vm.prank(address(endpoints[ARB_EID]));
        yieldZeroComposer_arb.lzCompose{value: MIN_RETURN_GAS + EXTRA_GAS_BUFFER}(
            address(shareOFT_arb), receipt.guid, wrappedMsg, address(0), ""
        );

        verifyPackets(ETH_EID, _addressToBytes32(address(assetOFT_eth)));
        assertEq(assetOFT_eth.balanceOf(userA), TOKENS_TO_SEND);
    }

    function test_redeemFromSpokeReceiveOnHub() public {
        // Deposit first to get shares on Ethereum
        _fundLocalFromHub(address(yieldZeroComposer_arb), TOKENS_TO_SEND);
        vm.prank(address(yieldZeroComposer_arb));
        vault_arb.deposit(TOKENS_TO_SEND, address(yieldZeroComposer_arb));

        SendParam memory sendToEth = _buildHopParam(userA, address(yieldZeroComposer_arb), ETH_EID);
        MessagingFee memory feeEth = shareOFT_arb.quoteSend(sendToEth, false);
        deal(address(yieldZeroComposer_arb), feeEth.nativeFee);
        vm.prank(address(yieldZeroComposer_arb));
        shareOFT_arb.send{value: feeEth.nativeFee}(sendToEth, feeEth, address(yieldZeroComposer_arb));
        verifyPackets(ETH_EID, _addressToBytes32(address(shareOFT_eth)));

        // Redeem from Ethereum (spoke) and receive assets on Arbitrum (hub)
        SendParam memory hopParam = _buildHopParam(userA, address(yieldZeroComposer_arb), ARB_EID);
        bytes memory composePayload = abi.encode(hopParam, MIN_RETURN_GAS);

        SendParam memory redeemParam = SendParam({
            dstEid: ARB_EID,
            to: _addressToBytes32(address(yieldZeroComposer_arb)),
            amountLD: TOKENS_TO_SEND,
            minAmountLD: (TOKENS_TO_SEND * 99) / 100,
            extraOptions: OPTIONS_LZRECEIVE_500k,
            composeMsg: composePayload,
            oftCmd: ""
        });

        vm.prank(userA);
        shareOFT_eth.approve(address(shareOFT_eth), TOKENS_TO_SEND);
        MessagingFee memory feeRedeem = shareOFT_eth.quoteSend(redeemParam, false);
        deal(userA, feeRedeem.nativeFee + 1 ether);

        vm.prank(userA);
        (MessagingReceipt memory receipt,) =
            shareOFT_eth.send{value: feeRedeem.nativeFee}(redeemParam, feeRedeem, userA);

        deal(address(endpoints[ARB_EID]), 1 ether);
        verifyPackets(ARB_EID, _addressToBytes32(address(shareOFT_arb)));

        bytes32 sourceOft = _addressToBytes32(address(shareOFT_eth));
        bytes memory wrappedMsg =
            abi.encodePacked(uint64(receipt.nonce), uint32(ETH_EID), TOKENS_TO_SEND, sourceOft, composePayload);

        vm.prank(address(endpoints[ARB_EID]));
        yieldZeroComposer_arb.lzCompose{value: MIN_RETURN_GAS + EXTRA_GAS_BUFFER}(
            address(shareOFT_arb), receipt.guid, wrappedMsg, address(0), ""
        );

        verifyPackets(ARB_EID, _addressToBytes32(address(assetOFT_arb)));
        assertEq(assetOFT_arb.balanceOf(userA), TOKENS_TO_SEND);
    }
}
