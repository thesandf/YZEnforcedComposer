// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {OFTComposeMsgCodec} from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {EnforcedOptionParam} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppOptionsType3.sol";
import {IOFT, SendParam, MessagingFee, OFTReceipt} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {MessagingReceipt} from "@layerzerolabs/oft-evm/contracts/OFTCore.sol";

import {VaultComposerSync} from "@layerzerolabs/ovault-evm/contracts/VaultComposerSync.sol";

import {YieldZeroVault, YieldZeroShareOFTAdapter} from "../src/core/YieldZeroVault.sol";
import {YieldZeroComposer} from "../src/omnichain/YieldZeroComposer.sol";
import {YieldZeroAccessControl} from "../src/access/YieldZeroAccessControl.sol";
import {YieldZeroAssetOFT} from "../src/tokens/YieldZeroAssetOFT.sol";
import {YieldZeroShareOFT} from "../src/tokens/YieldZeroShareOFT.sol";

import "forge-std/console.sol";
import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";

contract YieldZeroBaseTest is TestHelperOz5 {
    using OptionsBuilder for bytes;

    uint8 subMeshSize = 3;

    uint32 public constant ETH_EID = 1;
    uint32 public constant ARB_EID = 2;
    uint32 public constant POL_EID = 3;

    YieldZeroAssetOFT public assetOFT_arb;
    YieldZeroShareOFTAdapter public shareOFT_arb;

    YieldZeroAssetOFT public assetOFT_eth;
    YieldZeroShareOFT public shareOFT_eth;

    YieldZeroAssetOFT public assetOFT_pol;
    YieldZeroShareOFT public shareOFT_pol;

    YieldZeroVault public vault_arb;
    YieldZeroComposer public yieldZeroComposer_arb;
    YieldZeroAccessControl public accessControl;

    address public userA = makeAddr("userA");
    address public userB = makeAddr("userB");

    bytes public OPTIONS_LZRECEIVE_100k = OptionsBuilder.newOptions().addExecutorLzReceiveOption(100_000, 0);

    bytes public OPTIONS_LZRECEIVE_500k = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0)
        .addExecutorLzComposeOption(0, 500_000, 0.001 ether);

    uint256 public constant INITIAL_BALANCE = 100 ether;
    uint256 public constant TOKENS_TO_SEND = 1 ether;

    uint256 public constant msgValueToFail = 100_000 wei;
    uint256 public constant msgValueToPass = 250_000_000 wei;

    function setUp() public virtual override {
        super.setUp();
        setUpEndpoints(subMeshSize, LibraryType.UltraLightNode);

        /// @dev Deploy the Asset OFT - ETH will be HUB chain, others are SPOKE
        assetOFT_arb = new YieldZeroAssetOFT("YieldZero Asset", "YZA", address(endpoints[ARB_EID]), address(this), true); // HUB
        assetOFT_eth =
            new YieldZeroAssetOFT("YieldZero Asset", "YZA", address(endpoints[ETH_EID]), address(this), false); //SPOKE
        assetOFT_pol =
            new YieldZeroAssetOFT("YieldZero Asset", "YZA", address(endpoints[POL_EID]), address(this), false); // SPOKE

        // config and wire the ofts
        address[] memory assetOFTs = new address[](subMeshSize);
        assetOFTs[0] = address(assetOFT_eth);
        assetOFTs[1] = address(assetOFT_arb);
        assetOFTs[2] = address(assetOFT_pol);
        this.wireOApps(assetOFTs);

        // Deploy access control and wire into vault/composer
        accessControl = new YieldZeroAccessControl(address(this));

        vault_arb = new YieldZeroVault(
            "YieldZero Share", "YZS", IERC20(address(assetOFT_arb)), address(this), address(accessControl)
        );
        shareOFT_arb = new YieldZeroShareOFTAdapter(address(vault_arb), address(endpoints[ARB_EID]), address(this));
        yieldZeroComposer_arb = new YieldZeroComposer(
            address(vault_arb), address(assetOFT_arb), address(shareOFT_arb), address(this), address(accessControl)
        );

        // Grant CONFIG_MANAGER_ROLE to deployer
        accessControl.grantConfigManagerRole(address(this), "Test config manager");

        // Set composer using config manager role
        vm.prank(address(this));
        vault_arb.setComposer(address(yieldZeroComposer_arb));

        /// Deploy the Share OFTs on other networks
        shareOFT_eth = new YieldZeroShareOFT("YieldZero Share", "YZS", address(endpoints[ETH_EID]), address(this));
        shareOFT_pol = new YieldZeroShareOFT("YieldZero Share", "YZS", address(endpoints[POL_EID]), address(this));

        address[] memory shareOFTs = new address[](subMeshSize);
        shareOFTs[0] = address(shareOFT_eth);
        shareOFTs[1] = address(shareOFT_arb);
        shareOFTs[2] = address(shareOFT_pol);
        this.wireOApps(shareOFTs);

        vm.label(address(assetOFT_arb), "AssetOFT::arb");
        vm.label(address(assetOFT_eth), "AssetOFT::eth");
        vm.label(address(assetOFT_pol), "AssetOFT::pol");

        vm.label(address(shareOFT_arb), "ShareOFTAdapter::arb");
        vm.label(address(shareOFT_eth), "ShareOFT::eth");
        vm.label(address(shareOFT_pol), "ShareOFT::pol");

        vm.label(address(vault_arb), "Vault::arb");
        vm.label(address(yieldZeroComposer_arb), "VaultComposerSync::arb");

        EnforcedOptionParam[] memory enforcedOptions = new EnforcedOptionParam[](3);
        enforcedOptions[0] = EnforcedOptionParam({eid: POL_EID, msgType: 1, options: OPTIONS_LZRECEIVE_100k});
        enforcedOptions[1] = EnforcedOptionParam({eid: ARB_EID, msgType: 1, options: OPTIONS_LZRECEIVE_100k});
        enforcedOptions[2] = EnforcedOptionParam({eid: ETH_EID, msgType: 1, options: OPTIONS_LZRECEIVE_100k});

        assetOFT_arb.setEnforcedOptions(enforcedOptions);
        assetOFT_eth.setEnforcedOptions(enforcedOptions);
        assetOFT_pol.setEnforcedOptions(enforcedOptions);

        shareOFT_arb.setEnforcedOptions(enforcedOptions);
        shareOFT_eth.setEnforcedOptions(enforcedOptions);
        shareOFT_pol.setEnforcedOptions(enforcedOptions);

        // Set min deposit size to a very small value for testing purposes
        yieldZeroComposer_arb.setMinDepositSize(1); // 1 wei
    }

    function _fundFromHub(address user, uint256 amount, uint32 dstEid) internal {
        SendParam memory sendParam = _buildHopParam(address(assetOFT_arb), user, dstEid, amount);
        MessagingFee memory fee = assetOFT_arb.quoteSend(sendParam, false);
        assetOFT_arb.send{value: fee.nativeFee}(sendParam, fee, payable(address(this)));
        
        // Verify the packets are delivered to ensure the user gets the tokens
        if (dstEid == ETH_EID) {
            verifyPackets(dstEid, OFTComposeMsgCodec.addressToBytes32(address(assetOFT_eth)));
        } else if (dstEid == POL_EID) {
            verifyPackets(dstEid, OFTComposeMsgCodec.addressToBytes32(address(assetOFT_pol)));
        } else if (dstEid == ARB_EID) {
            // For hub chain, transfer directly
            assetOFT_arb.transfer(user, amount);
        } else {
            revert("Unsupported chain EID");
        }
    }

    function _fundLocalFromHub(address user, uint256 amount) internal {
        assetOFT_arb.transfer(user, amount);
    }

    function _fundLocalFromHub(address user, uint256 amount, uint32 dstEid) internal {
        if (dstEid == ARB_EID) {
            assetOFT_arb.transfer(user, amount);
        } else if (dstEid == ETH_EID) {
            // For spoke chains, we need to first send from hub to spoke
            SendParam memory sendParam = _buildHopParam(address(assetOFT_arb), user, dstEid, amount);
            MessagingFee memory fee = assetOFT_arb.quoteSend(sendParam, false);
            assetOFT_arb.send{value: fee.nativeFee}(sendParam, fee, payable(address(this)));
            // Verify the packets are delivered
            verifyPackets(dstEid, OFTComposeMsgCodec.addressToBytes32(address(assetOFT_eth)));
        } else if (dstEid == POL_EID) {
            // For spoke chains, we need to first send from hub to spoke
            SendParam memory sendParam = _buildHopParam(address(assetOFT_arb), user, dstEid, amount);
            MessagingFee memory fee = assetOFT_arb.quoteSend(sendParam, false);
            assetOFT_arb.send{value: fee.nativeFee}(sendParam, fee, payable(address(this)));
            // Verify the packets are delivered
            verifyPackets(dstEid, OFTComposeMsgCodec.addressToBytes32(address(assetOFT_pol)));
        } else {
            revert("Unsupported chain EID");
        }
    }

    function _buildHopParam(address composer, address user, uint32 dstEid, uint256 amount)
        internal
        pure
        virtual
        returns (SendParam memory)
    {
        return SendParam({
            dstEid: dstEid,
            to: OFTComposeMsgCodec.addressToBytes32(user),
            amountLD: amount,
            minAmountLD: amount,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });
    }
}
