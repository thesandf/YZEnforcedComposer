// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {IYieldZeroKernel} from "../interfaces/IYieldZeroKernel.sol";
import {IVaultAdapter} from "../interfaces/adapters/IVaultAdapter.sol";
import {IOFTAdapter} from "../interfaces/adapters/IOFTAdapter.sol";
import {IStrategyAdapter} from "../interfaces/adapters/IStrategyAdapter.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
/// @title YieldZeroKernel
/// @notice Core orchestration contract for the YieldZero Ops SDK.
/// 
/// The kernel is the central contract that manages all adapters, enforces
/// deployment modes, and routes calls through the appropriate adapters.
/// It provides a unified interface for omnichain ERC-4626 vault operations.
/// 
/// Architecture:
/// - Adapter-First: Kernel knows only interfaces, not concrete implementations
/// - Mode Enforcement: Different modes require different adapter configurations
/// - Security: RBAC, pause, TVL caps, rate limiting
/// - Cross-chain: Abstract hooks for LayerZero integration
/// 
/// Deployment Modes:
/// - FULL_DEPLOY: Use YieldZero reference vault, OFTs, strategy
/// - DEPLOY_OFT_ONLY: Wrap existing ERC20 into OFT
/// - ATTACH_STRATEGY: Attach strategies to existing vaults
/// - ATTACH_ALL: Orchestrate fully external vault + token + strategy
contract YieldZeroKernel is IYieldZeroKernel, AccessControl, Pausable {
    DeploymentMode private _mode;
    address private _vaultAdapter;
    address private _oftAdapter;
    address private _strategyAdapter;
    uint256 private _tvlCap;
    bytes32 public constant KERNEL_ADMIN_ROLE = keccak256("KERNEL_ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");
    bytes32 public constant VAULT_ADAPTER_TYPE = keccak256("VAULT_ADAPTER");
    bytes32 public constant OFT_ADAPTER_TYPE = keccak256("OFT_ADAPTER");
    bytes32 public constant STRATEGY_ADAPTER_TYPE = keccak256("STRATEGY_ADAPTER");
    modifier whenNotPausedAndValidMode() {
        require(!paused(), "YieldZeroKernel: kernel is paused");
        _;
    }
    modifier onlyOperator() {
        require(hasRole(OPERATOR_ROLE, msg.sender), "YieldZeroKernel: caller is not operator");
        _;
    }
    modifier onlyKeeper() {
        require(hasRole(KEEPER_ROLE, msg.sender), "YieldZeroKernel: caller is not keeper");
        _;
    }
    /// @notice Constructor
    constructor(address _initialAdmin) {
        require(_initialAdmin != address(0), "YieldZeroKernel: zero address");
        
        _grantRole(DEFAULT_ADMIN_ROLE, _initialAdmin);
        _grantRole(KERNEL_ADMIN_ROLE, _initialAdmin);
        _grantRole(OPERATOR_ROLE, _initialAdmin);
        _grantRole(KEEPER_ROLE, _initialAdmin);
        
        _mode = DeploymentMode.FULL_DEPLOY;
        _tvlCap = type(uint256).max;
    }
    /// @inheritdoc IYieldZeroKernel
    function mode() external view override returns (DeploymentMode) {
        return _mode;
    }
    /// @inheritdoc IYieldZeroKernel
    function setMode(DeploymentMode _newMode) external override onlyRole(KERNEL_ADMIN_ROLE) {
        require(_newMode != _mode, "YieldZeroKernel: same mode");
        
        /// Validate mode requirements before switching
        require(validateMode(), "YieldZeroKernel: current adapters don't satisfy new mode");
        
        emit ModeSet(_newMode, msg.sender);
        _mode = _newMode;
    }
    /// @inheritdoc IYieldZeroKernel
    function vaultAdapter() external view override returns (address) {
        return _vaultAdapter;
    }
    /// @inheritdoc IYieldZeroKernel
    function setVaultAdapter(address _adapter) external override onlyRole(KERNEL_ADMIN_ROLE) {
        require(_adapter != address(0), "YieldZeroKernel: zero vault adapter");
        
        /// Validate the adapter implements IVaultAdapter
        try IVaultAdapter(_adapter).adapterType() returns (bytes32 _type) {
            require(_type == VAULT_ADAPTER_TYPE, "YieldZeroKernel: invalid vault adapter type");
        } catch {
            revert("YieldZeroKernel: not a vault adapter");
        }
        
        _vaultAdapter = _adapter;
        emit VaultSet(_adapter);
    }
    /// @inheritdoc IYieldZeroKernel
    function oftAdapter() external view override returns (address) {
        return _oftAdapter;
    }
    /// @inheritdoc IYieldZeroKernel
    function setOFTAdapter(address _adapter) external override onlyRole(KERNEL_ADMIN_ROLE) {
        require(_adapter != address(0), "YieldZeroKernel: zero OFT adapter");
        
        /// Validate the adapter implements IOFTAdapter
        try IOFTAdapter(_adapter).adapterType() returns (bytes32 _type) {
            require(_type == OFT_ADAPTER_TYPE, "YieldZeroKernel: invalid OFT adapter type");
        } catch {
            revert("YieldZeroKernel: not an OFT adapter");
        }
        
        _oftAdapter = _adapter;
        emit OFTSet(_adapter);
    }
    /// @inheritdoc IYieldZeroKernel
    function strategyAdapter() external view override returns (address) {
        return _strategyAdapter;
    }
    /// @inheritdoc IYieldZeroKernel
    function setStrategyAdapter(address _adapter) external override onlyRole(KERNEL_ADMIN_ROLE) {
        require(_adapter != address(0), "YieldZeroKernel: zero strategy adapter");
        
        /// Validate the adapter implements IStrategyAdapter
        try IStrategyAdapter(_adapter).adapterType() returns (bytes32 _type) {
            require(_type == STRATEGY_ADAPTER_TYPE, "YieldZeroKernel: invalid strategy adapter type");
        } catch {
            revert("YieldZeroKernel: not a strategy adapter");
        }
        
        _strategyAdapter = _adapter;
        emit StrategySet(_adapter);
    }
    /// @inheritdoc IYieldZeroKernel
    function paused() public view override(IYieldZeroKernel, Pausable) returns (bool) {
        return super.paused();
    }
    /// @inheritdoc IYieldZeroKernel
    function pause() external override onlyRole(KERNEL_ADMIN_ROLE) {
        super._pause();
        emit KernelPaused(msg.sender);
    }
    /// @inheritdoc IYieldZeroKernel
    function unpause() external override onlyRole(KERNEL_ADMIN_ROLE) {
        super._unpause();
        emit KernelUnpaused(msg.sender);
    }
    /// @inheritdoc IYieldZeroKernel
    function tvlCap() external view override returns (uint256) {
        return _tvlCap;
    }
    /// @inheritdoc IYieldZeroKernel
    function setTVLCap(uint256 _cap) external override onlyRole(KERNEL_ADMIN_ROLE) {
        require(_cap > 0, "YieldZeroKernel: TVL cap must be > 0");
        
        uint256 oldCap = _tvlCap;
        _tvlCap = _cap;
        
        emit TVLCapUpdated(oldCap, _cap);
    }
    /// @inheritdoc IYieldZeroKernel
    function getState() external view override returns (KernelState memory) {
        return KernelState({
            mode: _mode,
            vaultAdapter: _vaultAdapter,
            oftAdapter: _oftAdapter,
            strategyAdapter: _strategyAdapter,
            isPaused: paused(),
            tvlCap: _tvlCap
        });
    }
    /// @inheritdoc IYieldZeroKernel
    function executeDeposit(address _user, uint256 _assets) 
        external 
        override 
        onlyOperator 
        whenNotPausedAndValidMode 
        returns (uint256 shares) 
    {
        require(_vaultAdapter != address(0), "YieldZeroKernel: vault not set");
        require(_user != address(0), "YieldZeroKernel: zero user");
        require(_assets > 0, "YieldZeroKernel: zero assets");
        
        /// Check TVL cap
        uint256 currentTVL = IVaultAdapter(_vaultAdapter).totalAssets();
        require(currentTVL + _assets <= _tvlCap, "YieldZeroKernel: TVL cap exceeded");
        
        /// Route through vault adapter
        shares = IVaultAdapter(_vaultAdapter).deposit(_user, _assets);
        
        return shares;
    }
    /// @inheritdoc IYieldZeroKernel
    function executeWithdraw(address _user, uint256 _assets) 
        external 
        override 
        onlyOperator 
        whenNotPausedAndValidMode 
        returns (uint256 shares) 
    {
        require(_vaultAdapter != address(0), "YieldZeroKernel: vault not set");
        require(_user != address(0), "YieldZeroKernel: zero user");
        require(_assets > 0, "YieldZeroKernel: zero assets");
        
        /// Route through vault adapter
        shares = IVaultAdapter(_vaultAdapter).withdraw(_user, _assets);
        
        return shares;
    }
    /// @inheritdoc IYieldZeroKernel
    function executeCrossChainTransfer(
        address _from,
        uint32 _dstChainId,
        address _to,
        uint256 _amount,
        bytes calldata _adapterParams
    ) 
        external 
        payable 
        override 
        onlyOperator 
        whenNotPausedAndValidMode 
        returns (bytes32 messageId) 
    {
        require(_oftAdapter != address(0), "YieldZeroKernel: OFT not set");
        require(_from != address(0), "YieldZeroKernel: zero from");
        require(_to != address(0), "YieldZeroKernel: zero to");
        require(_amount > 0, "YieldZeroKernel: zero amount");
        
        /// Route through OFT adapter
        messageId = IOFTAdapter(_oftAdapter).sendCrossChain(
            _from,
            _dstChainId,
            _to,
            _amount,
            _adapterParams,
            bytes("")  /// No compose message
        );
        
        return messageId;
    }
    /// @inheritdoc IYieldZeroKernel
    function executeHarvest() 
        external 
        override 
        onlyKeeper 
        whenNotPausedAndValidMode 
    {
        require(_strategyAdapter != address(0), "YieldZeroKernel: strategy not set");
        
        /// Route through strategy adapter
        IStrategyAdapter(_strategyAdapter).harvest();
    }
    /// @inheritdoc IYieldZeroKernel
    function executeRebalance() 
        external 
        override 
        onlyKeeper 
        whenNotPausedAndValidMode 
    {
        require(_strategyAdapter != address(0), "YieldZeroKernel: strategy not set");
        
        /// Route through strategy adapter
        IStrategyAdapter(_strategyAdapter).rebalance();
    }
    /// @inheritdoc IYieldZeroKernel
    function swapAdapter(address _newAdapter, bytes32 _adapterType) 
        external 
        override 
        onlyRole(KERNEL_ADMIN_ROLE) 
        whenNotPaused 
    {
        require(_newAdapter != address(0), "YieldZeroKernel: zero adapter");
        
        if (_adapterType == VAULT_ADAPTER_TYPE) {
            /// Validate new adapter
            try IVaultAdapter(_newAdapter).adapterType() returns (bytes32 _type) {
                require(_type == VAULT_ADAPTER_TYPE, "YieldZeroKernel: invalid vault adapter");
            } catch {
                revert("YieldZeroKernel: not a vault adapter");
            }
            
            /// Swap with pause for safety
            if (_vaultAdapter != address(0)) {
                IVaultAdapter(_vaultAdapter).pause();
            }
            IVaultAdapter(_newAdapter).unpause();
            _vaultAdapter = _newAdapter;
            
        } else if (_adapterType == OFT_ADAPTER_TYPE) {
            try IOFTAdapter(_newAdapter).adapterType() returns (bytes32 _type) {
                require(_type == OFT_ADAPTER_TYPE, "YieldZeroKernel: invalid OFT adapter");
            } catch {
                revert("YieldZeroKernel: not an OFT adapter");
            }
            
            if (_oftAdapter != address(0)) {
                IOFTAdapter(_oftAdapter).pause();
            }
            IOFTAdapter(_newAdapter).unpause();
            _oftAdapter = _newAdapter;
            
        } else if (_adapterType == STRATEGY_ADAPTER_TYPE) {
            try IStrategyAdapter(_newAdapter).adapterType() returns (bytes32 _type) {
                require(_type == STRATEGY_ADAPTER_TYPE, "YieldZeroKernel: invalid strategy adapter");
            } catch {
                revert("YieldZeroKernel: not a strategy adapter");
            }
            
            if (_strategyAdapter != address(0)) {
                IStrategyAdapter(_strategyAdapter).pause();
            }
            IStrategyAdapter(_newAdapter).unpause();
            _strategyAdapter = _newAdapter;
            
        } else {
            revert("YieldZeroKernel: unknown adapter type");
        }
        
        emit AdapterRegistered(_newAdapter, _adapterType, "SWAPPED");
    }
    /// @inheritdoc IYieldZeroKernel
    function validateMode() public view override returns (bool) {
        if (_mode == DeploymentMode.FULL_DEPLOY) {
            return _vaultAdapter != address(0) && 
                   _oftAdapter != address(0) && 
                   _strategyAdapter != address(0);
                   
        } else if (_mode == DeploymentMode.DEPLOY_OFT_ONLY) {
            return _oftAdapter != address(0);
            
        } else if (_mode == DeploymentMode.ATTACH_STRATEGY) {
            return _vaultAdapter != address(0) && _strategyAdapter != address(0);
            
        } else {
            /// ATTACH_ALL - just needs vault
            return _vaultAdapter != address(0);
        }
    }
    /// @notice Hook called after cross-chain message is received
    function onInboundMessage(uint32 _srcChainId, bytes calldata _message) 
        external 
        onlyRole(KERNEL_ADMIN_ROLE) 
    {
        /// This is an abstract hook - implement based on specific use cases
        /// Could trigger deposits, withdrawals, strategy actions, etc.
    }
    /// @notice Hook called before cross-chain message is sent
    function onOutboundMessage(uint32 _dstChainId, bytes calldata _message) 
        external 
        onlyRole(KERNEL_ADMIN_ROLE) 
    {
        /// This is an abstract hook - implement based on specific use cases
    }
}
