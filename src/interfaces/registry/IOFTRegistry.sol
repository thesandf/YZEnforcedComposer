// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
/// @title IOFTRegistry
/// @notice Interface for the OFT Registry.
/// 
/// The OFT Registry manages OFT (Omnichain Fungible Token) deployments,
/// tracking chain configurations, trusted remotes, and bridging configurations.
interface IOFTRegistry {
    /// @notice OFT info struct
    struct OFTInfo {
        address oftAddress;
        address token;
        string name;
        string symbol;
        uint8 decimals;
        bool isActive;
        uint32[] supportedChains;
        uint256 registeredAt;
    }
    /// @notice Emitted when an OFT is registered
    event OFTRegistered(
        address indexed oft,
        address indexed token,
        string name
    );
    /// @notice Emitted when an OFT is removed
    event OFTRemoved(address indexed oft);
    /// @notice Emitted when OFT status changes
    event OFTStatusChanged(address indexed oft, bool isActive);
    /// @notice Emitted when supported chain is added
    event SupportedChainAdded(address indexed oft, uint32 chainId);
    /// @notice Emitted when trusted remote is set
    event TrustedRemoteSet(address indexed oft, uint32 remoteChainId, bytes path);
    /// @notice Register a new OFT
    function registerOFT(
        address _oft,
        address _token,
        string calldata _name,
        string calldata _symbol,
        uint8 _decimals
    ) external;
    /// @notice Remove an OFT
    function removeOFT(address _oft) external;
    /// @notice Set OFT active status
    function setOFTStatus(address _oft, bool _isActive) external;
    /// @notice Add supported chain
    function addSupportedChain(address _oft, uint32 _chainId) external;
    /// @notice Set trusted remote
    function setTrustedRemote(
        address _oft,
        uint32 _remoteChainId,
        bytes calldata _path
    ) external;
    /// @notice Get OFT info
    function getOFTInfo(address _oft) external view returns (OFTInfo memory);
    /// @notice Get OFT by token
    function getOFTByToken(address _token) external view returns (address);
    /// @notice Get all registered OFTs
    function getAllOFTs() external view returns (address[] memory);
    /// @notice Get supported chains for an OFT
    function getSupportedChains(address _oft) external view returns (uint32[] memory);
    /// @notice Check if OFT is registered
    function isRegistered(address _oft) external view returns (bool);
    /// @notice Check if chain is supported
    function isChainSupported(address _oft, uint32 _chainId) external view returns (bool);
}
