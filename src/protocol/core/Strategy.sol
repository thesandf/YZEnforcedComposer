// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IStrategy
 * @notice Abstract interface for pluggable yield strategies
 * @dev Allows YieldZeroVault to integrate with various yield protocols (Yearn, Beefy, Pendle)
 *
 */
interface IStrategy {
    /**
     * @notice The underlying asset this strategy accepts
     */
    function asset() external view returns (IERC20);

    /**
     * @notice Total assets managed by this strategy
     */
    function totalAssets() external view returns (uint256);

    /**
     * @notice Deposit assets into the strategy
     */
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    /**
     * @notice Redeem strategy shares for assets
     */
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);

    /**
     * @notice Harvest yield and reinvest
     */
    function harvest() external returns (uint256 yield);

    /**
     * @notice Convert strategy shares to assets
     */
    function convertToAssets(uint256 shares) external view returns (uint256);

    /**
     * @notice Convert assets to strategy shares
     */
    function convertToShares(uint256 assets) external view returns (uint256);
}

/**
 * @title BaseStrategy
 * @notice Base implementation of IStrategy with common logic
 * @dev All yield strategies should inherit from this
 */
abstract contract BaseStrategy is IStrategy {
    IERC20 public immutable _asset;

    event StrategyDeposit(address indexed user, uint256 assets, uint256 shares);
    event StrategyRedeem(address indexed user, uint256 shares, uint256 assets);
    event StrategyHarvest(address indexed harvester, uint256 yield);

    constructor(IERC20 _underlyingAsset) {
        _asset = _underlyingAsset;
    }

    function asset() external view returns (IERC20) {
        return _asset;
    }

    /**
     * @dev Override in subclasses to implement strategy logic
     */
    function deposit(uint256 assets, address receiver) external virtual returns (uint256 shares);

    /**
     * @dev Override in subclasses to implement strategy logic
     */
    function redeem(uint256 shares, address receiver, address owner) external virtual returns (uint256 assets);

    /**
     * @dev Override in subclasses to implement yield harvesting
     */
    function harvest() external virtual returns (uint256 yield);

    function convertToAssets(uint256 shares) external view virtual returns (uint256);
    function convertToShares(uint256 assets) external view virtual returns (uint256);
}
