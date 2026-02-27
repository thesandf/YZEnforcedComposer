// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {OFTAdapter} from "@layerzerolabs/oft-evm/contracts/OFTAdapter.sol";
import {YieldZeroAccessControl} from "../access/YieldZeroAccessControl.sol";

import {
    YZVault_Paused,
    YZVault_ZeroReceiver,
    YZVault_ZeroAmount,
    YZVault_ZeroShares,
    YZVault_CallerNotComposer,
    YZVault_InvalidAccessControl,
    YZVault_InvalidComposer,
    YZAccessControl_CallerNotConfigManager,
    YZVault_PreviewMismatch,
    YZVault_InsufficientShares,
    YZVault_InsufficientAssets,
    YZVault_ZeroEmergencyAmount
} from "../errors/Errors.sol";

/**
 * @title YieldZeroVault
 * @notice ERC4626-compliant tokenized vault for omnichain yield farming
 * @dev This is the HUB contract that manages deposits/redeems from spoke chains
 */

contract YieldZeroVault is ERC4626, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Access control contract
    YieldZeroAccessControl public accessControl;

    /// @notice Total yield accumulated
    uint256 public totalYieldAccumulated;

    address public composer;

    /// @notice Whether the vault is paused
    bool public isPaused;

    event VaultPaused(bool indexed paused);
    event YieldAccumulated(uint256 amount);
    event AssetsWithdrawn(address indexed to, uint256 amount);
    event ComposerUpdated(address indexed oldComposer, address indexed newComposer);
    event Redeem(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    modifier whenNotPaused() {
        if (isPaused) revert YZVault_Paused();
        _;
    }

    modifier onlyComposer() {
        if (msg.sender != composer) revert YZVault_CallerNotComposer();
        _;
    }

    modifier onlyConfigManager() {
        if (accessControl.hasRole(accessControl.CONFIG_MANAGER_ROLE(), msg.sender) == false) {
            revert YZAccessControl_CallerNotConfigManager();
        }
        _;
    }

    /**
     * @notice Creates a new ERC4626 vault
     */
    constructor(string memory _name, string memory _symbol, IERC20 _asset, address _owner, address _accessControl)
        ERC20(_name, _symbol)
        ERC4626(_asset)
        Ownable(_owner)
    {
        if (_accessControl == address(0)) revert YZVault_InvalidAccessControl();
        accessControl = YieldZeroAccessControl(_accessControl);
    }

    function setComposer(address _composer) external onlyConfigManager {
        if (_composer == address(0)) revert YZVault_InvalidComposer();
        address oldComposer = composer;
        composer = _composer;
        emit ComposerUpdated(oldComposer, _composer);
    }

    /**
     * @notice Pause/unpause the vault
     */
    function setPaused(bool _paused) external onlyConfigManager {
        isPaused = _paused;
        emit VaultPaused(_paused);
    }

    /**
     * @notice Get total assets in the vault
     */
    function totalAssets() public view override returns (uint256) {
        // In production: idle balance + deployed in strategies
        return IERC20(asset()).balanceOf(address(this));
    }

    /**
     * @notice Deposit assets into the vault
     */
    function deposit(uint256 assets, address receiver)
        public
        override
        onlyComposer
        whenNotPaused
        nonReentrant
        returns (uint256 shares)
    {
        if (assets == 0) revert YZVault_ZeroAmount();
        if (receiver == address(0)) revert YZVault_ZeroReceiver();

        // Calculate shares using the preview function
        shares = previewDeposit(assets);
        if (shares == 0) revert YZVault_PreviewMismatch();

        // Transfer assets from caller (composer) to vault
        SafeERC20.safeTransferFrom(IERC20(asset()), msg.sender, address(this), assets);

        // Mint shares directly to the receiver (composer)
        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
        return shares;
    }

    /**
     * @notice Redeem shares from the vault
     */
    function redeem(uint256 shares, address receiver, address owner)
        public
        override
        onlyComposer
        whenNotPaused
        nonReentrant
        returns (uint256 assets)
    {
        if (shares == 0) revert YZVault_ZeroShares();
        if (receiver == address(0)) revert YZVault_ZeroReceiver();
        if (balanceOf(owner) < shares) {
            revert YZVault_InsufficientShares();
        }
        // Calculate assets using the preview function
        assets = previewRedeem(shares);

        uint256 vaultBal = IERC20(asset()).balanceOf(address(this));
        if (vaultBal < assets) {
            revert YZVault_InsufficientAssets();
        }

        // Burn shares from the owner (composer)
        _burn(owner, shares);

        // Transfer assets from vault to receiver
        SafeERC20.safeTransfer(IERC20(asset()), receiver, assets);

        emit Redeem(msg.sender, receiver, owner, assets, shares);
        return assets;
    }

    /**
     * @notice Emergency function to withdraw assets from the vault
     */
    function emergencyWithdraw(uint256 amount, address to) external onlyOwner nonReentrant {
        if (to == address(0)) revert YZVault_ZeroReceiver();
        if (amount == 0) revert YZVault_ZeroEmergencyAmount();
        SafeERC20.safeTransfer(IERC20(asset()), to, amount);
        emit AssetsWithdrawn(to, amount);
    }

    /**
     * @notice Get vault stats for analytics
     */
    function getVaultStats() external view returns (uint256 totalAssets_, uint256 totalShares_, uint256 totalYield_) {
        return (totalAssets(), totalSupply(), totalYieldAccumulated);
    }
}

/**
 * @title YieldZeroShareOFTAdapter
 * @notice OFT adapter for vault shares enabling cross-chain transfers
 */

contract YieldZeroShareOFTAdapter is OFTAdapter {
    constructor(
        address _vault, // address of YieldZeroVault (ERC20 shares)
        address _lzEndpoint,
        address _delegate
    )
        OFTAdapter(_vault, _lzEndpoint, _delegate)
        Ownable(_delegate)
    {}
}
