// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {VaultComposerSync} from "@layerzerolabs/ovault-evm/contracts/VaultComposerSync.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IOFT, SendParam, MessagingFee} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {OFTComposeMsgCodec} from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import {RateLimiter} from "../security/RateLimiter.sol";
import {YieldZeroAccessControl} from "../access/YieldZeroAccessControl.sol";
import {
    YZComposer_ZeroAmount,
    YZComposer_BelowMinimum,
    YZComposer_AboveMaximum,
    YZComposer_ZeroAddress,
    YZComposer_InvalidDestination,
    YZComposer_InsufficientTVL,
    YZComposer_SlippageExceeded,
    YZComposer_RateLimited,
    YZComposer_InsufficientBalance,
    YZComposer_CallerNotConfigManager,
    YZComposer_InvalidAccessControl,
    YZComposer_PreviewMismatch,
    YZComposer_TVLInvariantBroken
} from 

"../errors/Errors.sol";

/**
 * @title YieldZeroComposer
 * @notice Cross-chain vault composer enabling omnichain deposit/redeem operations
 * @dev Implements VaultComposerSync for synchronized cross-chain vault operations
 */
contract YieldZeroComposer is VaultComposerSync, Ownable {
    using SafeERC20 for IERC20;
    using OFTComposeMsgCodec for bytes32;

    /// @notice Access control contract
    YieldZeroAccessControl public accessControl;

    /// @notice Rate limiter contract for preventing abuse
    address public rateLimiter;

    uint256 public maxDepositSize = type(uint256).max;

    uint256 public minDepositSize = 1e18; // 1 (18 decimals)

    /// @notice Total value locked by users
    uint256 public totalValueLocked;

    function _enforceTVLInvariant() internal view {
        if (totalValueLocked > VAULT.totalAssets()) {
            revert YZComposer_TVLInvariantBroken();
        }
    }

    event MaxDepositSizeUpdated(uint256 newSize);
    event MinDepositSizeUpdated(uint256 newSize);
    event RateLimiterUpdated(address newRateLimiter);
    event UserDepositRecorded(address indexed user, uint256 amount, uint32 dstEid);
    event UserRedeemRecorded(address indexed user, uint256 amount, uint32 dstEid);
    event TVLUpdated(uint256 indexed newTVL, address indexed user, uint256 amount, bool indexed isDeposit);

    /// @notice Modifier to check CONFIG_MANAGER role
    modifier onlyConfigManager() {
        if (accessControl.hasRole(accessControl.CONFIG_MANAGER_ROLE(), msg.sender) == false) {
            revert YZComposer_CallerNotConfigManager();
        }
        _;
    }

    /**
     * @notice Creates a new cross-chain vault composer
     * @dev Initializes the composer with vault and OFT contracts
     */
    constructor(address _vault, address _assetOFT, address _shareOFT, address _owner, address _accessControl)
        VaultComposerSync(_vault, _assetOFT, _shareOFT)
        Ownable(_owner)
    {
        if (_accessControl == address(0)) revert YZComposer_InvalidAccessControl();
        accessControl = YieldZeroAccessControl(_accessControl);
    }

    /**
     * @notice Initiate a deposit from a spoke chain
     * @param _assetAmount Amount of assets to deposit
     * @param _minSharesOut Minimum shares to receive (slippage protection)
     * @param _sendParam Parameters for cross-chain send
     * @param _refundAddress Address to refund excess fees (must not be address(0))
     */
    function initiateDepositAndSend(
        uint256 _assetAmount,
        uint256 _minSharesOut,
        SendParam memory _sendParam,
        address _refundAddress
    ) external payable nonReentrant {
        if (_assetAmount == 0) revert YZComposer_ZeroAmount();
        if (_assetAmount < minDepositSize) revert YZComposer_BelowMinimum();
        if (_assetAmount > maxDepositSize) revert YZComposer_AboveMaximum();
        if (_refundAddress == address(0)) revert YZComposer_ZeroAddress();
        if (_sendParam.dstEid == 0) revert YZComposer_InvalidDestination();

        // Check rate limiting if rate limiter is set
        if (rateLimiter != address(0)) {
            RateLimiter limiter = RateLimiter(rateLimiter);
            if (!limiter.canOperate(msg.sender)) {
                revert YZComposer_RateLimited();
            }
        }

        uint256 expectedShares = VAULT.previewDeposit(_assetAmount);
        if (expectedShares == 0) revert YZComposer_PreviewMismatch();
        if (expectedShares < _minSharesOut) revert YZComposer_SlippageExceeded();

        // Transfer assets from user to composer
        IERC20(ASSET_ERC20).safeTransferFrom(msg.sender, address(this), _assetAmount);

        totalValueLocked += _assetAmount;

        _depositAndSend(
            OFTComposeMsgCodec.addressToBytes32(msg.sender), _assetAmount, _sendParam, _refundAddress, msg.value
        );

        _enforceTVLInvariant();

        // Record operation after successful deposit
        if (rateLimiter != address(0)) {
            RateLimiter(rateLimiter).recordOperation(msg.sender);
        }

        emit TVLUpdated(totalValueLocked, msg.sender, _assetAmount, true);
        emit UserDepositRecorded(msg.sender, _assetAmount, _sendParam.dstEid);
    }

    /**
     * @notice Initiate a redemption from a spoke chain
     * @dev Called when ShareOFT receives shares from a spoke
     * @param _shareAmount Amount of shares to redeem
     * @param _minAssetsOut Minimum assets to receive (slippage protection)
     * @param _sendParam Parameters for cross-chain send
     * @param _refundAddress Address to refund excess fees (must not be address(0))
     */
    function initiateRedeemAndSend(
        uint256 _shareAmount,
        uint256 _minAssetsOut,
        SendParam memory _sendParam,
        address _refundAddress
    ) external payable nonReentrant {
        if (_shareAmount == 0) revert YZComposer_ZeroAmount();
        if (_shareAmount < minDepositSize) revert YZComposer_BelowMinimum();
        if (_shareAmount > maxDepositSize) revert YZComposer_AboveMaximum();
        if (_refundAddress == address(0)) revert YZComposer_ZeroAddress();
        if (_sendParam.dstEid == 0) revert YZComposer_InvalidDestination();

        // Check rate limiting if rate limiter is set
        if (rateLimiter != address(0)) {
            RateLimiter limiter = RateLimiter(rateLimiter);
            if (!limiter.canOperate(msg.sender)) {
                revert YZComposer_RateLimited();
            }
        }

        uint256 expectedAssets = VAULT.previewRedeem(_shareAmount);
        if (expectedAssets == 0) revert YZComposer_PreviewMismatch();
        if (expectedAssets < _minAssetsOut) revert YZComposer_SlippageExceeded();

        // Transfer shares from user to composer
        IERC20(SHARE_ERC20).safeTransferFrom(msg.sender, address(this), _shareAmount);

        if (expectedAssets > totalValueLocked) {
            totalValueLocked = 0;
        } else {
            totalValueLocked -= expectedAssets;
        }

        _redeemAndSend(
            OFTComposeMsgCodec.addressToBytes32(msg.sender), _shareAmount, _sendParam, _refundAddress, msg.value
        );

        _enforceTVLInvariant();

        // Record operation after successful redeem
        if (rateLimiter != address(0)) {
            RateLimiter(rateLimiter).recordOperation(msg.sender);
        }

        emit TVLUpdated(totalValueLocked, msg.sender, expectedAssets, false);
        emit UserRedeemRecorded(msg.sender, _shareAmount, _sendParam.dstEid);
    }

    /**
     * @notice Get TVL across all chains
     */
    function getTotalValueLocked() external view returns (uint256 tvl) {
        return totalValueLocked;
    }

    /**
     * @notice Get user's total shares balance
     */
    function getUserShares(address _user) external view returns (uint256 shares) {
        // In production: sum shares across all chains
        return IERC20(SHARE_ERC20).balanceOf(_user);
    }

    /**
     * @notice Get user's assets value
     */
    function getUserAssets(address _user) external view returns (uint256 assets) {
        uint256 shares = IERC20(SHARE_ERC20).balanceOf(_user);
        return VAULT.convertToAssets(shares);
    }

    /**
     * @notice Set the rate limiter contract
     */
    function setRateLimiter(address _rateLimiter) external onlyConfigManager {
        rateLimiter = _rateLimiter;
        emit RateLimiterUpdated(_rateLimiter);
    }

    /**
     * @notice Update max deposit size
     */
    function setMaxDepositSize(uint256 _newSize) external onlyConfigManager {
        if (_newSize == 0) revert YZComposer_ZeroAmount();
        maxDepositSize = _newSize;
        emit MaxDepositSizeUpdated(_newSize);
    }

    /**
     * @notice Update min deposit size
     */
    function setMinDepositSize(uint256 _newSize) external onlyConfigManager {
        if (_newSize == 0) revert YZComposer_ZeroAmount();
        minDepositSize = _newSize;
        emit MinDepositSizeUpdated(_newSize);
    }

    /**
     * @notice Emergency function to withdraw stuck assets
     */
    function emergencyWithdraw(uint256 _amount, address _to) external onlyOwner {
        if (_to == address(0)) revert YZComposer_ZeroAddress();
        if (_amount == 0) revert YZComposer_ZeroAmount();
        if (_amount > IERC20(ASSET_ERC20).balanceOf(address(this))) revert YZComposer_InsufficientBalance();

        // Update TVL before transfer (checks-effects-interactions)
        if (_amount <= totalValueLocked) {
            totalValueLocked -= _amount;
            _enforceTVLInvariant();
            emit TVLUpdated(totalValueLocked, address(0), _amount, false);
        }

        IERC20(ASSET_ERC20).safeTransfer(_to, _amount);
    }

    /**
     * @notice Emergency function to withdraw stuck shares
     */
    function emergencyWithdrawShares(uint256 _amount, address _to) external onlyOwner nonReentrant {
        if (_to == address(0)) revert YZComposer_ZeroAddress();
        if (_amount == 0) revert YZComposer_ZeroAmount();
        if (_amount > IERC20(SHARE_ERC20).balanceOf(address(this))) revert YZComposer_InsufficientBalance();

        IERC20(SHARE_ERC20).safeTransfer(_to, _amount);
    }

    /**
     * @notice Invariant check: Total value locked should match vault's total assets
     */
    function invariantCheck() external view returns (bool isValid) {
        uint256 vaultAssets = VAULT.totalAssets();
        if (totalValueLocked > vaultAssets) return false;
        return true;
    }
}
