// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {IVaultAdapter} from "./adapters/IVaultAdapter.sol";
import {IOFTAdapter} from "./adapters/IOFTAdapter.sol";
import {IStrategyAdapter} from "./adapters/IStrategyAdapter.sol";
/// @title IYieldZeroKernel
/// @notice Core interface for the YieldZero Kernel.
/// 
/// The kernel is the central orchestration contract that manages
/// all adapters, enforces deployment modes, and routes calls
/// through the appropriate adapters.
interface IYieldZeroKernel {
    /// @notice Deployment modes supported by the SDK
    enum DeploymentMode {
        FULL_DEPLOY,      /// Use YieldZero reference vault, OFTs, strategy
        DEPLOY_OFT_ONLY, /// Wrap existing ERC20 into OFT
        ATTACH_STRATEGY, /// Attach strategies to existing vaults
        ATTACH_ALL       /// Orchestrate fully external vault + token + strategy
    }
    /// @notice Kernel state
    struct KernelState {
        DeploymentMode mode;
        address vaultAdapter;
        address oftAdapter;
        address strategyAdapter;
        bool isPaused;
        uint256 tvlCap;
    }
    /// @notice Emitted when an adapter is registered
    event AdapterRegistered(address indexed adapter, bytes32 indexed adapterType, string name);
    /// @notice Emitted when an adapter is removed
    event AdapterRemoved(address indexed adapter, bytes32 indexed adapterType);
    /// @notice Emitted when deployment mode is set
    event ModeSet(DeploymentMode indexed mode, address indexed caller);
    /// @notice Emitted when vault is set
    event VaultSet(address indexed vaultAdapter);
    /// @notice Emitted when OFT is set
    event OFTSet(address indexed oftAdapter);
    /// @notice Emitted when strategy is set
    event StrategySet(address indexed strategyAdapter);
    /// @notice Emitted when TVL cap is updated
    event TVLCapUpdated(uint256 oldCap, uint256 newCap);
    /// @notice Emitted when kernel is paused
    event KernelPaused(address indexed caller);
    /// @notice Emitted when kernel is unpaused
    event KernelUnpaused(address indexed caller);
    /// @notice Get the current deployment mode
    function mode() external view returns (DeploymentMode);
    /// @notice Get the current vault adapter
    function vaultAdapter() external view returns (address);
    /// @notice Get the current OFT adapter
    function oftAdapter() external view returns (address);
    /// @notice Get the current strategy adapter
    function strategyAdapter() external view returns (address);
    /// @notice Check if the kernel is paused
    function paused() external view returns (bool);
    /// @notice Get the TVL cap
    function tvlCap() external view returns (uint256);
    /// @notice Get the current state
    function getState() external view returns (KernelState memory);
    /// @notice Set the deployment mode
    function setMode(DeploymentMode _mode) external;
    /// @notice Set vault adapter
    function setVaultAdapter(address _adapter) external;
    /// @notice Set OFT adapter
    function setOFTAdapter(address _adapter) external;
    /// @notice Set strategy adapter
    function setStrategyAdapter(address _adapter) external;
    /// @notice Set TVL cap
    function setTVLCap(uint256 _cap) external;
    /// @notice Pause the kernel
    function pause() external;
    /// @notice Unpause the kernel
    function unpause() external;
    /// @notice Execute a deposit through the kernel
    function executeDeposit(address _user, uint256 _assets) external returns (uint256 shares);
    /// @notice Execute a withdraw through the kernel
    function executeWithdraw(address _user, uint256 _assets) external returns (uint256 shares);
    /// @notice Execute a cross-chain transfer
    function executeCrossChainTransfer(
        address _from,
        uint32 _dstChainId,
        address _to,
        uint256 _amount,
        bytes calldata _adapterParams
    ) external payable returns (bytes32 messageId);
    /// @notice Execute strategy harvest
    function executeHarvest() external;
    /// @notice Execute strategy rebalance
    function executeRebalance() external;
    /// @notice Swap adapter (for upgrades)
    function swapAdapter(address _newAdapter, bytes32 _adapterType) external;
    /// @notice Validate mode requirements are met
    function validateMode() external view returns (bool);
}
