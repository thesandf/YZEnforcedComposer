// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
/// @title IAdapterRegistry
/// @notice Interface for the Adapter Registry.
/// 
/// The Adapter Registry maintains a mapping of adapter types to their
/// implementations, allowing the kernel to discover and use different
/// vault, OFT, and strategy adapters.
interface IAdapterRegistry {
    /// @notice Adapter info struct
    struct AdapterInfo {
        address adapterAddress;
        string name;
        bytes32 adapterType;
        bool isActive;
        uint256 registeredAt;
    }
    /// @notice Emitted when an adapter is registered
    event AdapterRegistered(
        address indexed adapter,
        bytes32 indexed adapterType,
        string name
    );
    /// @notice Emitted when an adapter is removed
    event AdapterRemoved(address indexed adapter, bytes32 indexed adapterType);
    /// @notice Emitted when an adapter is activated/deactivated
    event AdapterStatusChanged(
        address indexed adapter,
        bytes32 indexed adapterType,
        bool isActive
    );
    /// @notice Register a new adapter
    function registerAdapter(
        address _adapter,
        string calldata _name,
        bytes32 _adapterType
    ) external;
    /// @notice Remove an adapter
    function removeAdapter(address _adapter, bytes32 _adapterType) external;
    /// @notice Set adapter active status
    function setAdapterStatus(address _adapter, bool _isActive) external;
    /// @notice Get adapter by type
    function getAdapterByType(bytes32 _adapterType) external view returns (address);
    /// @notice Get adapter info
    function getAdapterInfo(address _adapter) external view returns (AdapterInfo memory);
    /// @notice Get all adapters of a specific type
    function getAdaptersByType(bytes32 _adapterType) external view returns (address[] memory);
    /// @notice Check if adapter is registered
    function isRegistered(address _adapter) external view returns (bool);
    /// @notice Get total adapter count
    function adapterCount() external view returns (uint256);
}
