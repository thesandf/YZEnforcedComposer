// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
/// @title IStrategyRegistry
/// @notice Interface for the Strategy Registry.
/// 
/// The Strategy Registry manages approved strategies that can be attached
/// to vaults, tracking performance, risk scores, and allocations.
interface IStrategyRegistry {
    /// @notice Strategy info struct
    struct StrategyInfo {
        address strategyAddress;
        string name;
        bytes32 strategyType;
        bool isActive;
        uint256 tvlAllocated;
        uint256 registeredAt;
        uint256 riskScore;
    }
    /// @notice Emitted when a strategy is registered
    event StrategyRegistered(
        address indexed strategy,
        bytes32 indexed strategyType,
        string name,
        uint256 riskScore
    );
    /// @notice Emitted when a strategy is removed
    event StrategyRemoved(address indexed strategy);
    /// @notice Emitted when strategy status changes
    event StrategyStatusChanged(address indexed strategy, bool isActive);
    /// @notice Emitted when TVL allocation is updated
    event TVLAllocationUpdated(address indexed strategy, uint256 oldTVL, uint256 newTVL);
    /// @notice Register a new strategy
    function registerStrategy(
        address _strategy,
        string calldata _name,
        bytes32 _strategyType,
        uint256 _riskScore
    ) external;
    /// @notice Remove a strategy
    function removeStrategy(address _strategy) external;
    /// @notice Set strategy active status
    function setStrategyStatus(address _strategy, bool _isActive) external;
    /// @notice Update TVL allocation
    function updateTVLAllocation(address _strategy, uint256 _newTVL) external;
    /// @notice Get strategy info
    function getStrategyInfo(address _strategy) external view returns (StrategyInfo memory);
    /// @notice Get strategy by type
    function getStrategyByType(bytes32 _strategyType) external view returns (address);
    /// @notice Get all strategies
    function getAllStrategies() external view returns (address[] memory);
    /// @notice Get total TVL across all strategies
    function totalTVL() external view returns (uint256);
    /// @notice Check if strategy is registered
    function isRegistered(address _strategy) external view returns (bool);
    /// @notice Get strategies by risk score range
    function getStrategiesByRiskScore(uint256 _minRisk, uint256 _maxRisk) external view returns (address[] memory);
}
