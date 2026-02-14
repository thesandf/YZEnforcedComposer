// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
/// @title IStrategyAdapter
/// @notice Interface for yield strategy adapters in the YieldZero Ops SDK.
/// 
/// Strategy adapters manage the underlying assets deposited into vaults,
/// handling yield generation, rebalancing, and harvesting. The kernel
/// interacts with strategies through this abstract interface, allowing
/// any yield-generating strategy to be plugged in.
interface IStrategyAdapter {
    /// @notice Adapter type identifier for strategies
    function adapterType() external pure returns (bytes32);
    /// @notice The asset token this strategy manages
    function wantToken() external view returns (address);
    /// @notice The vault this strategy is attached to
    function vault() external view returns (address);
    /// @notice Total assets deposited in the strategy
    function totalDeposits() external view returns (uint256);
    /// @notice Current estimated yield earned (unrealized)
    function estimatedTotalAssets() external view returns (uint256);
    /// @notice Check if the strategy is active
    function isActive() external view returns (bool);
    /// @notice Deposit want tokens into the strategy
    function deposit(uint256 _amount) external returns (uint256 deposited);
    /// @notice Withdraw want tokens from the strategy
    function withdraw(uint256 _amount) external returns (uint256 withdrawn);
    /// @notice Harvest yield and report profits to the vault
    function harvest() external;
    /// @notice Rebalance the strategy (move funds between markets)
    function rebalance() external;
    /// @notice Sweep excess tokens that aren't part of the strategy
    function sweep(address _token) external returns (uint256 swept);
    /// @notice Initialize the adapter with strategy parameters
    function initialize(address _vault, address _wantToken, bytes calldata _data) external;
    /// @notice Migrate to a new strategy
    function migrate(address _newStrategy) external;
    /// @notice Emergency exit the strategy
    function emergencyExit() external;
    /// @notice Pause strategy operations
    function pause() external;
    /// @notice Unpause strategy operations
    function unpause() external;
    /// @notice Get strategy performance metrics
    function getPerformance() external view returns (
        uint256 totalYield,
        uint256 lastHarvestTimestamp,
        uint256 apy
    );
}
