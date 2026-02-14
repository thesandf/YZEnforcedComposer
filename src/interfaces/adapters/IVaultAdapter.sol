// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
/// @title IVaultAdapter
/// @notice Interface for vault adapters in the YieldZero Ops SDK.
/// 
/// The kernel interacts with vaults through this adapter interface,
/// allowing any ERC4626-compatible vault to be integrated without
/// the kernel needing to know concrete implementation details.
///  *
/// Adapters encapsulate all vault-specific logic and provide a
/// unified interface for deposit, withdraw, asset management, etc.
interface IVaultAdapter {
    /// @notice Adapter type identifier for vaults
    function adapterType() external pure returns (bytes32);
    /// @notice The underlying asset token address
    function asset() external view returns (address);
    /// @notice The vault share token address
    function shares() external view returns (address);
    /// @notice Total assets managed by the vault
    function totalAssets() external view returns (uint256);
    /// @notice Convert shares to assets
    function convertToAssets(uint256 shares) external view returns (uint256);
    /// @notice Convert assets to shares
    function convertToShares(uint256 assets) external view returns (uint256);
    /// @notice Deposit assets into the vault
    function deposit(address caller, uint256 assets) external returns (uint256 shares);
    /// @notice Withdraw assets from the vault
    function withdraw(address caller, uint256 assets) external returns (uint256 shares);
    /// @notice Mint shares from the vault
    function mint(address caller, uint256 shares) external returns (uint256 assets);
    /// @notice Redeem shares from the vault
    function redeem(address caller, uint256 shares) external returns (uint256 assets);
    /// @notice Check if the vault is operational
    function isActive() external view returns (bool);
    /// @notice Get the vault's underlying ERC4626 interface
    function vault() external view returns (IERC4626);
    /// @notice Initialize the adapter with a vault address
    function initialize(address _vault) external;
    /// @notice Pause vault operations
    function pause() external;
    /// @notice Unpause vault operations
    function unpause() external;
}
