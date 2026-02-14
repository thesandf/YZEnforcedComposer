// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {IYieldZeroKernel} from "../interfaces/IYieldZeroKernel.sol";
/// @title ModeRouter
/// @notice Routes operations based on deployment mode in the YieldZero Ops SDK.
/// 
/// The ModeRouter enforces mode requirements and routes calls to the
/// appropriate adapters based on the current deployment mode.
/// 
/// Deployment Modes:
/// - FULL_DEPLOY: Use YieldZero reference vault, OFTs, strategy
/// - DEPLOY_OFT_ONLY: Wrap existing ERC20 into OFT
/// - ATTACH_STRATEGY: Attach strategies to existing vaults
/// - ATTACH_ALL: Orchestrate fully external vault + token + strategy
contract ModeRouter {
    /// @notice Mode requirements mapping
    mapping(IYieldZeroKernel.DeploymentMode => bytes32) private _modeRequirements;
    /// @notice Deployment mode constants
    bytes32 public constant MODE_FULL_DEPLOY = keccak256("FULL_DEPLOY");
    bytes32 public constant MODE_DEPLOY_OFT_ONLY = keccak256("DEPLOY_OFT_ONLY");
    bytes32 public constant MODE_ATTACH_STRATEGY = keccak256("ATTACH_STRATEGY");
    bytes32 public constant MODE_ATTACH_ALL = keccak256("ATTACH_ALL");
    /// @notice Adapter type requirements per mode
    bytes32 public constant VAULT_ADAPTER = keccak256("VAULT_ADAPTER");
    bytes32 public constant OFT_ADAPTER = keccak256("OFT_ADAPTER");
    bytes32 public constant STRATEGY_ADAPTER = keccak256("STRATEGY_ADAPTER");
    constructor() {
        /// Set up mode requirements
        /// FULL_DEPLOY requires all three adapters
        _modeRequirements[IYieldZeroKernel.DeploymentMode.FULL_DEPLOY] = 
            keccak256(abi.encodePacked(VAULT_ADAPTER, OFT_ADAPTER, STRATEGY_ADAPTER));
        
        /// DEPLOY_OFT_ONLY only requires OFT adapter
        _modeRequirements[IYieldZeroKernel.DeploymentMode.DEPLOY_OFT_ONLY] = 
            keccak256(abi.encodePacked(OFT_ADAPTER));
        
        /// ATTACH_STRATEGY requires vault and strategy adapters
        _modeRequirements[IYieldZeroKernel.DeploymentMode.ATTACH_STRATEGY] = 
            keccak256(abi.encodePacked(VAULT_ADAPTER, STRATEGY_ADAPTER));
        
        /// ATTACH_ALL can work with any combination (flexible)
        _modeRequirements[IYieldZeroKernel.DeploymentMode.ATTACH_ALL] = 
            keccak256(abi.encodePacked(VAULT_ADAPTER));
    }
    /// @notice Get the required adapters for a given mode
    /// @return Required adapter types as bytes32 array
    function getRequiredAdapters(IYieldZeroKernel.DeploymentMode _mode) 
        external 
        view 
        returns (bytes32[] memory) 
    {
        bytes32 requirement = _modeRequirements[_mode];
        
        /// Parse the requirement and return individual adapter types
        if (_mode == IYieldZeroKernel.DeploymentMode.FULL_DEPLOY) {
            bytes32[] memory adapters = new bytes32[](3);
            adapters[0] = VAULT_ADAPTER;
            adapters[1] = OFT_ADAPTER;
            adapters[2] = STRATEGY_ADAPTER;
            return adapters;
        } else if (_mode == IYieldZeroKernel.DeploymentMode.DEPLOY_OFT_ONLY) {
            bytes32[] memory adapters = new bytes32[](1);
            adapters[0] = OFT_ADAPTER;
            return adapters;
        } else if (_mode == IYieldZeroKernel.DeploymentMode.ATTACH_STRATEGY) {
            bytes32[] memory adapters = new bytes32[](2);
            adapters[0] = VAULT_ADAPTER;
            adapters[1] = STRATEGY_ADAPTER;
            return adapters;
        } else {
            /// ATTACH_ALL - at minimum needs vault
            bytes32[] memory adapters = new bytes32[](1);
            adapters[0] = VAULT_ADAPTER;
            return adapters;
        }
    }
    /// @notice Validate if the current adapter configuration matches the mode requirements
    /// @return True if configuration is valid for the mode
    function validateModeConfiguration(
        IYieldZeroKernel.DeploymentMode _mode,
        bool _hasVault,
        bool _hasOFT,
        bool _hasStrategy
    ) external pure returns (bool) {
        if (_mode == IYieldZeroKernel.DeploymentMode.FULL_DEPLOY) {
            return _hasVault && _hasOFT && _hasStrategy;
        } else if (_mode == IYieldZeroKernel.DeploymentMode.DEPLOY_OFT_ONLY) {
            return _hasOFT;
        } else if (_mode == IYieldZeroKernel.DeploymentMode.ATTACH_STRATEGY) {
            return _hasVault && _hasStrategy;
        } else {
            /// ATTACH_ALL - needs at least vault
            return _hasVault;
        }
    }
    /// @notice Get mode requirement description
    /// @return Human-readable description of required adapters
    function getModeDescription(IYieldZeroKernel.DeploymentMode _mode) 
        external 
        pure 
        returns (string memory) 
    {
        if (_mode == IYieldZeroKernel.DeploymentMode.FULL_DEPLOY) {
            return "FULL_DEPLOY requires: Vault Adapter, OFT Adapter, Strategy Adapter";
        } else if (_mode == IYieldZeroKernel.DeploymentMode.DEPLOY_OFT_ONLY) {
            return "DEPLOY_OFT_ONLY requires: OFT Adapter";
        } else if (_mode == IYieldZeroKernel.DeploymentMode.ATTACH_STRATEGY) {
            return "ATTACH_STRATEGY requires: Vault Adapter, Strategy Adapter";
        } else {
            return "ATTACH_ALL requires: Vault Adapter (flexible)";
        }
    }
    /// @notice Check if a specific adapter is required for a mode
    /// @return True if the adapter is required
    function isAdapterRequiredForMode(
        IYieldZeroKernel.DeploymentMode _mode,
        bytes32 _adapterType
    ) external pure returns (bool) {
        if (_mode == IYieldZeroKernel.DeploymentMode.FULL_DEPLOY) {
            return _adapterType == VAULT_ADAPTER || 
                   _adapterType == OFT_ADAPTER || 
                   _adapterType == STRATEGY_ADAPTER;
        } else if (_mode == IYieldZeroKernel.DeploymentMode.DEPLOY_OFT_ONLY) {
            return _adapterType == OFT_ADAPTER;
        } else if (_mode == IYieldZeroKernel.DeploymentMode.ATTACH_STRATEGY) {
            return _adapterType == VAULT_ADAPTER || 
                   _adapterType == STRATEGY_ADAPTER;
        } else {
            /// ATTACH_ALL - only vault is strictly required
            return _adapterType == VAULT_ADAPTER;
        }
    }
}
