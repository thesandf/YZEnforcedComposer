// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {YZReader_InvalidAddress} from "../errors/Errors.sol";
/// @title YieldZeroReader
/// @notice Cross-chain data aggregator for YieldZero protocol
/// @dev Provides read-only access to vault and composer state across chains
/// Top-level interface declarations
interface IVault {
    function totalAssets() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
}
interface IComposer {
    function getTotalValueLocked() external view returns (uint256);
    function getUserShares(address user) external view returns (uint256);
    function getUserAssets(address user) external view returns (uint256);
}
interface IHub {
    function isPaused() external view returns (bool);
    function feeBasisPoints() external view returns (uint256);
    function totalFeesCollected() external view returns (uint256);
    function lastHarvestTime() external view returns (uint256);
}
contract YieldZeroReader {
    /// @notice Vault address
    address public vault;
    /// @notice Composer address
    address public composer;
    /// @notice Hub address
    address public hub;
    /// @notice Asset token
    address public asset;
    event VaultAddressUpdated(address newVault);
    event ComposerAddressUpdated(address newComposer);
    event HubAddressUpdated(address newHub);
    constructor(address _vault, address _composer, address _hub, address _asset) {
        if (_vault == address(0)) revert YZReader_InvalidAddress();
        if (_composer == address(0)) revert YZReader_InvalidAddress();
        if (_hub == address(0)) revert YZReader_InvalidAddress();
        if (_asset == address(0)) revert YZReader_InvalidAddress();
        vault = _vault;
        composer = _composer;
        hub = _hub;
        asset = _asset;
    }
    /// @notice Get total value locked across all chains
    /// @return tvl Total TVL in native units (e.g., USDC wei)
    function getTotalValueLocked() external view returns (uint256 tvl) {
        return IComposer(composer).getTotalValueLocked();
    }
    /// @notice Get user's total shares
    /// @return shares Total shares held
    function getUserTotalShares(address _user) external view returns (uint256 shares) {
        return IComposer(composer).getUserShares(_user);
    }
    /// @notice Get user's total assets value
    /// @return assets Total assets value
    function getUserTotalAssets(address _user) external view returns (uint256 assets) {
        return IComposer(composer).getUserAssets(_user);
    }
    /// @notice Get vault exchange rate (shares per asset)
    /// @return rate Exchange rate (e.g., 1.05 = 1 asset = 1.05 shares)
    function getExchangeRate() external view returns (uint256 rate) {
        IVault v = IVault(vault);
        uint256 totalAssets = v.totalAssets();
        uint256 totalShares = v.totalSupply();
        if (totalAssets == 0 || totalShares == 0) {
            return 1e18; /// 1:1 ratio
        }
        /// rate = totalShares / totalAssets (in wei)
        return (totalShares * 1e18) / totalAssets;
    }
    /// @notice Get vault APY (simplified - in production use actual yield history)
/// @dev This is a placeholder - real APY requires historical data
    /// @return apy APY in basis points (100 = 1%)
    function getVaultAPY() external view returns (uint256 apy) {
        /// Placeholder: would need historical yield data
        /// Real implementation: (totalYield / TVL) / days * 365 * 10000
        return 0;
    }
    /// @notice Get vault fee configuration
    /// @return feeBasisPoints Fee in basis points
    function getVaultFee() external view returns (uint256 feeBasisPoints) {
        return IHub(hub).feeBasisPoints();
    }
    /// @notice Get vault status
    /// @return paused Whether vault is paused
    /// @return totalAssets Total assets in vault
    /// @return totalShares Total shares issued
    /// @return tvl Total value locked across all chains
    function getVaultStatus()
        external
        view
        returns (bool paused, uint256 totalAssets, uint256 totalShares, uint256 tvl)
    {
        IVault v = IVault(vault);
        IHub h = IHub(hub);
        IComposer c = IComposer(composer);
        return (h.isPaused(), v.totalAssets(), v.totalSupply(), c.getTotalValueLocked());
    }
    /// @notice Convert assets to shares
    /// @return shares Equivalent shares
    function convertToShares(uint256 _assets) external view returns (uint256 shares) {
        return IVault(vault).convertToShares(_assets);
    }
    /// @notice Convert shares to assets
    /// @return assets Equivalent assets
    function convertToAssets(uint256 _shares) external view returns (uint256 assets) {
        return IVault(vault).convertToAssets(_shares);
    }
    /// @notice Get user's balance in assets
    /// @return assets User's balance in assets
    function getUserBalanceInAssets(address _user) external view returns (uint256 assets) {
        IVault v = IVault(vault);
        uint256 shares = v.balanceOf(_user);
        return v.convertToAssets(shares);
    }
    /// @notice Get last harvest time
    /// @return timestamp Last harvest timestamp
    function getLastHarvestTime() external view returns (uint256 timestamp) {
        return IHub(hub).lastHarvestTime();
    }
    /// @notice Get total fees collected
    /// @return fees Total fees in assets
    function getTotalFeesCollected() external view returns (uint256 fees) {
        return IHub(hub).totalFeesCollected();
    }
    /// @notice Update vault address
    function setVaultAddress(address _newVault) external {
        if (_newVault == address(0)) revert YZReader_InvalidAddress();
        vault = _newVault;
        emit VaultAddressUpdated(_newVault);
    }
    /// @notice Update composer address
    function setComposerAddress(address _newComposer) external {
        if (_newComposer == address(0)) revert YZReader_InvalidAddress();
        composer = _newComposer;
        emit ComposerAddressUpdated(_newComposer);
    }
    /// @notice Update hub address
    function setHubAddress(address _newHub) external {
        if (_newHub == address(0)) revert YZReader_InvalidAddress();
        hub = _newHub;
        emit HubAddressUpdated(_newHub);
    }
}
