// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
/// @title IOFTAdapter
/// @notice Interface for OFT (Omnichain Fungible Token) adapters in the YieldZero Ops SDK.
/// 
/// OFT adapters handle cross-chain token transfers via LayerZero.
/// The adapter provides a unified interface for sending/receiving tokens
/// across different blockchain networks without the kernel knowing
/// about the underlying OFT implementation.
interface IOFTAdapter {
    /// @notice Adapter type identifier for OFTs
    function adapterType() external pure returns (bytes32);
    /// @notice The token address (could be native, ERC20, or OFT)
    function token() external view returns (address);
    /// @notice The OFT token address on the local chain
    function oftToken() external view returns (address);
    /// @notice Total supply across all chains
    function totalSupply() external view returns (uint256);
    /// @notice Check if the OFT adapter is operational
    function isActive() external view returns (bool);
    /// @notice Send tokens cross-chain via LayerZero
    function sendCrossChain(
        address _from,
        uint32 _dstChainId,
        address _to,
        uint256 _amount,
        bytes calldata _adapterParams,
        bytes calldata _composeMsg
    ) external payable returns (bytes32 messageId);
    /// @notice Quote the cross-chain message fee
    function quoteCrossChain(
        uint32 _dstChainId,
        uint256 _amount,
        bytes calldata _adapterParams,
        bool _payInLzToken
    ) external view returns (uint256 nativeFee, uint256 lzTokenFee);
    /// @notice Initialize the adapter with an OFT address
    function initialize(address _oft) external;
    /// @notice Set the trusted remote for cross-chain messaging
    function setTrustedRemote(uint32 _remoteChainId, bytes calldata _path) external;
    /// @notice Pause cross-chain operations
    function pause() external;
    /// @notice Unpause cross-chain operations
    function unpause() external;
    /// @notice Get the LayerZero endpoint address
    function lzEndpoint() external view returns (address);
    /// @notice Retrieve the pool data (for internal accounting)
    function poolData() external view returns (bytes memory);
}
