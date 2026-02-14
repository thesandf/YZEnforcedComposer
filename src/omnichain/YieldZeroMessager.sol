// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;
import {OApp} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {OAppOptionsType3} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OAppOptionsType3.sol";
import {MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OAppSender.sol";
import {OAppCore} from "@layerzerolabs/oapp-evm/contracts/oapp/OAppCore.sol";
import {IOAppCore} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
import {Origin} from "@layerzerolabs/oapp-evm/contracts/oapp/OAppReceiver.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    YZMessager_InvalidPeerAddress,
    YZMessager_InvalidEndpointId,
    YZMessager_InvalidHub,
    YZMessager_InvalidConstructorInputs,
    YZMessager_InvalidMessageType,
    YZMessager_InvalidFeeValue,
    YZMessager_NotAuthorized,
    YZMessager_PeerNotConfigured
} from "../errors/Errors.sol";
///  *
/// @title YieldZeroMessager
/// @notice LayerZero-based cross-chain messaging contract
/// @dev Handles communication between YieldZeroHub and spoke chains
contract YieldZeroMessager is OApp, OAppOptionsType3 {
    using SafeERC20 for IERC20;
    using OptionsBuilder for bytes;
    /// @notice Address of the YieldZeroHub contract
    address public yieldZeroHub;
    /// @notice Message types
    enum MessageType {
        STATE_SYNC,
        FEE_UPDATE,
        PAUSE_UPDATE,
        HARVEST_DISTRIBUTION,
        TVL_SYNC,
        EMERGENCY_STOP
    }
    event HubUpdated(address newHub);
    event MessageSent(uint32 indexed dstEid, MessageType indexed messageType, bytes data);
    event MessageReceived(uint32 indexed srcEid, MessageType indexed messageType, bytes data);
    event StateSynced(uint256 tvl, uint256 totalSupply, uint256 yieldAccumulated);
    event FeeUpdated(uint256 newFee);
    event PauseUpdated(bool paused);
    event HarvestDistributed(uint256 yieldAmount);
    event EmergencyStopped();
    /// @notice Initialize the messager contract
    constructor(address _endpoint, address _hub, address _owner)
        OApp(_endpoint, _owner) /// forwards OAppCore(_endpoint, _delegate) which forwards Ownable(initialOwner)
        Ownable(_owner) /// needed because OAppOptionsType3 also inherits from Ownable
    {
        if (_endpoint == address(0) || _hub == address(0) || _owner == address(0)) {
            revert YZMessager_InvalidConstructorInputs();
        }
        yieldZeroHub = _hub;
    }
    /// @notice Set the YieldZeroHub address
    function setHub(address _hub) external onlyOwner {
        if (_hub == address(0)) {
            revert YZMessager_InvalidHub();
        }
        yieldZeroHub = _hub;
        emit HubUpdated(_hub);
    }
    /// @notice Set peer address for a destination chain
    function setPeer(uint32 _eid, bytes32 _peerAddress) public override onlyOwner {
        if (_eid == 0 || _eid == block.chainid) {
            revert YZMessager_InvalidEndpointId();
        }
        if (_peerAddress == bytes32(0)) {
            revert YZMessager_InvalidPeerAddress();
        }
        super.setPeer(_eid, _peerAddress);
    }
    /// @notice Get peer address for a destination chain
    function getPeer(uint32 _eid) external view returns (bytes32) {
        return peers[_eid];
    }
    /// @notice Send state sync message to all connected spokes
    function sendStateSync(uint256 _tvl, uint256 _totalSupply, uint256 _yieldAccumulated) external payable {
        if (msg.sender != yieldZeroHub && msg.sender != owner()) {
            revert YZMessager_NotAuthorized();
        }
        bytes memory message = abi.encode(MessageType.STATE_SYNC, _tvl, _totalSupply, _yieldAccumulated);
        /// Send to all connected peers
        for (uint32 eid = 1; eid < 1000; eid++) {
            bytes32 peer = peers[eid];
            if (peer != bytes32(0)) {
                _sendMessage(eid, message);
            }
        }
    }
    ///      *
/// @notice Send fee update message to a specific spoke
    function sendFeeUpdate(uint32 _eid, uint256 _newFee) external payable {
        if (msg.sender != yieldZeroHub && msg.sender != owner()) {
            revert YZMessager_NotAuthorized();
        }
        if (peers[_eid] == bytes32(0)) {
            revert YZMessager_PeerNotConfigured();
        }
        if (_newFee > 10000) {
            revert YZMessager_InvalidFeeValue();
        }
        bytes memory message = abi.encode(MessageType.FEE_UPDATE, _newFee);
        _sendMessage(_eid, message);
    }
    ///      *
/// @notice Send pause/update message to a specific spoke
    function sendPauseUpdate(uint32 _eid, bool _paused) external payable {
        if (msg.sender != yieldZeroHub && msg.sender != owner()) {
            revert YZMessager_NotAuthorized();
        }
        if (peers[_eid] == bytes32(0)) {
            revert YZMessager_PeerNotConfigured();
        }
        bytes memory message = abi.encode(MessageType.PAUSE_UPDATE, _paused);
        _sendMessage(_eid, message);
    }
    ///      *
/// @notice Send harvest distribution message to a specific spoke
    function sendHarvestDistribution(uint32 _eid, uint256 _yieldAmount) external payable {
        if (msg.sender != yieldZeroHub && msg.sender != owner()) {
            revert YZMessager_NotAuthorized();
        }
        if (peers[_eid] == bytes32(0)) {
            revert YZMessager_PeerNotConfigured();
        }
        bytes memory message = abi.encode(MessageType.HARVEST_DISTRIBUTION, _yieldAmount);
        _sendMessage(_eid, message);
    }
    /// @notice Send emergency stop message to all connected spokes
    function sendEmergencyStop() external payable {
        if (msg.sender != yieldZeroHub && msg.sender != owner()) {
            revert YZMessager_NotAuthorized();
        }
        bytes memory message = abi.encode(MessageType.EMERGENCY_STOP);
        for (uint32 eid = 1; eid < 1000; eid++) {
            bytes32 peer = peers[eid];
            if (peer != bytes32(0)) {
                _sendMessage(eid, message);
            }
        }
    }
    /// @notice Internal message sending logic
    function _sendMessage(uint32 _eid, bytes memory _message) internal {
        /// Configure messaging options (100k gas limit)
        bytes memory options = _buildOptions();
        /// Estimate and pay fees
        MessagingFee memory fee = _quote(_eid, _message, options, false);
        /// Send the message
        _lzSend(_eid, _message, options, fee, msg.sender);
        emit MessageSent(_eid, _getMessageType(_message), _message);
    }
    ///      *
/// @notice Handle received LayerZero messages
///      *
    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) internal override {
        MessageType msgType = _getMessageType(_message);
        emit MessageReceived(_origin.srcEid, msgType, _message);
        /// Process different message types
        if (msgType == MessageType.STATE_SYNC) {
            (, uint256 tvl, uint256 totalSupply, uint256 yieldAccumulated) =
                abi.decode(_message, (MessageType, uint256, uint256, uint256));
            _handleStateSync(tvl, totalSupply, yieldAccumulated);
        } else if (msgType == MessageType.FEE_UPDATE) {
            (, uint256 newFee) = abi.decode(_message, (MessageType, uint256));
            _handleFeeUpdate(newFee);
        } else if (msgType == MessageType.PAUSE_UPDATE) {
            (, bool paused) = abi.decode(_message, (MessageType, bool));
            _handlePauseUpdate(paused);
        } else if (msgType == MessageType.HARVEST_DISTRIBUTION) {
            (, uint256 yieldAmount) = abi.decode(_message, (MessageType, uint256));
            _handleHarvestDistribution(yieldAmount);
        } else if (msgType == MessageType.EMERGENCY_STOP) {
            _handleEmergencyStop();
        }
    }
    ///      *
/// @notice Extract message type from raw message
///      *
    function _getMessageType(bytes memory _message) internal pure returns (MessageType) {
        if (_message.length == 0) {
            revert YZMessager_InvalidMessageType();
        }
        return MessageType(uint8(_message[0]));
    }
    ///      *
/// @notice Build LayerZero options
///      *
    function _buildOptions() internal pure returns (bytes memory) {
        /// Set executor lzReceive option with 100k gas
        return OptionsBuilder.newOptions().addExecutorLzReceiveOption(100_000, 0);
    }
    ///      *
/// @notice Handle state sync messages
///      *
    function _handleStateSync(uint256 _tvl, uint256 _totalSupply, uint256 _yieldAccumulated) internal {
        /// Update local state with synced values
        emit StateSynced(_tvl, _totalSupply, _yieldAccumulated);
    }
    ///      *
/// @notice Handle fee update messages
///      *
    function _handleFeeUpdate(uint256 _newFee) internal {
        /// Update local fee configuration
        emit FeeUpdated(_newFee);
    }
    ///      *
/// @notice Handle pause update messages
///      *
    function _handlePauseUpdate(bool _paused) internal {
        /// Update pause state
        emit PauseUpdated(_paused);
    }
    ///      *
/// @notice Handle harvest distribution messages
///      *
    function _handleHarvestDistribution(uint256 _yieldAmount) internal {
        /// Handle yield distribution
        emit HarvestDistributed(_yieldAmount);
    }
    ///      *
/// @notice Handle emergency stop messages
///      *
    function _handleEmergencyStop() internal {
        /// Trigger emergency procedures
        emit EmergencyStopped();
    }
    /// @dev Override _payNative to accept any amount of native fee
    function _payNative(uint256 _nativeFee) internal virtual override returns (uint256 nativeFee) {
        /// For testing purposes, we accept any amount (including 0)
        if (_nativeFee == 0) {
            return 0;
        }
        if (msg.value < _nativeFee) revert YZMessager_InvalidFeeValue();
        return _nativeFee;
    }
    /// @notice Enable receiving ETH for fees
    receive() external payable {}
}
