// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {VaultComposerSync} from "@layerzerolabs/ovault-evm/contracts/VaultComposerSync.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {OFTComposeMsgCodec} from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

/**
 * @title YZEnforcedComposer
 * @author thesandf -(thesandf.eth@gmail.com)
 * @notice Execution-level risk enforcement for LayerZero V2 omnichain ERC4626 vaults
 * @dev Extends VaultComposerSync with TVL caps and user caps enforcement
 *
 * @dev CRITICAL CONSTRAINTS:
 *      - Overrides _depositAndSend() and _redeemAndSend() to add enforcement BEFORE vault operations
 *      - Does NOT duplicate refund logic (permissionless via VaultComposerSync)
 *      - Does NOT implement custom retry (permissionless via LayerZero)
 *      - Does NOT restrict LayerZero recovery
 *      - Slippage already handled by VaultComposerSync (_assertSlippage)
 *
 * @dev ARCHITECTURE:
 *      LayerZero V2 handles:
 *      - Message verification, DVN quorum, Replay protection
 *      - Retry (permissionless), Refund (permissionless)
 *      - Fee accounting, Compose wrapping
 *      - Slippage check via _assertSlippage()
 *
 *      YieldZero adds:
 *      - TVL cap enforcement
 *      - User deposit caps
 *      - Pause control
 *      - Whitelist mode
 */
contract YZEnforcedComposer is VaultComposerSync {
    using SafeERC20 for IERC20;
    using OFTComposeMsgCodec for bytes;
    using OFTComposeMsgCodec for bytes32;

    // ======== Errors ========

    error YZ_DepositsPaused();
    error YZ_RedemptionsPaused();
    error YZ_TVLCapExceeded(uint256 currentTVL, uint256 attemptedDeposit, uint256 tvlCap);
    error YZ_UserCapExceeded(address user, uint256 currentDeposit, uint256 attemptedDeposit, uint256 userCap);
    error YZ_NotWhitelisted(address user);
    error YZ_NotAdmin();
    error YZ_ZeroAddress();

    // ======== Version Tracking ========
    
    /// @notice Parent library version this contract was built against (for now only used for reference in tests to ensure correct override points)
    string public constant PARENT_VERSION_PINNED = "ovault-evm@1.0.0";

    // ======== State Variables ========

    /// @notice Admin address for configuration
    address public admin;

    /// @notice TVL cap (0 = unlimited)
    /// @dev Uses hub-chain vault.totalAssets() only. This is correct for OVault's
    ///      hub-and-spoke model where the ERC4626 vault lives exclusively on the hub chain.
    ///      All deposits from spoke chains flow through the composer to the hub vault,
    ///      so totalAssets() captures all TVL.
    uint256 public tvlCap;

    /// @notice Per-user deposit cap (0 = unlimited)
    mapping(address => uint256) public userDepositCap;

    /// @notice Track user deposits for cap enforcement
    mapping(address => uint256) public userDeposits;

    /// @notice Deposits paused state
    bool public depositsPaused;

    /// @notice Redemptions paused state (use with extreme caution)
    bool public redemptionsPaused;

    /// @notice Whitelist enabled
    bool public whitelistEnabled;

    /// @notice Whitelisted addresses
    mapping(address => bool) public whitelist;

    // ======== Events ========

    event TVLCapUpdated(uint256 indexed oldCap, uint256 indexed newCap);
    event UserCapUpdated(address indexed user, uint256 indexed oldCap, uint256 indexed newCap);
    event DepositsPaused(address indexed admin);
    event DepositsUnpaused(address indexed admin);
    event RedemptionsPaused(address indexed admin);
    event RedemptionsUnpaused(address indexed admin);
    event WhitelistEnabled(bool indexed enabled);
    event WhitelistUpdated(address indexed user, bool indexed status);
    event AdminUpdated(address indexed oldAdmin, address indexed newAdmin);
    event EnforcementExecuted(
        address indexed user,
        uint256 assets,
        uint256 tvlBefore,
        uint256 tvlAfter
    );
    event UserDepositTrackingReset(
        address indexed user,
        uint256 previousDeposit,
        uint256 redemptionAmount
    );

    // ======== Constructor ========

    /**
     * @notice Creates a new enforced composer
     * @param _vault Address of the ERC4626 vault (standard, no custom access)
     * @param _assetOFT Address of the asset OFT (standard OFT)
     * @param _shareOFT Address of the share OFT adapter (standard OFTAdapter)
     * @param _admin Admin address for configuration
     */
    constructor(
        address _vault,
        address _assetOFT,
        address _shareOFT,
        address _admin
    ) VaultComposerSync(_vault, _assetOFT, _shareOFT) {
        if (_admin == address(0)) revert YZ_ZeroAddress();
        admin = _admin;
    }

    // ======== Modifiers ========

    modifier onlyAdmin() {
        if (msg.sender != admin) revert YZ_NotAdmin();
        _;
    }

    modifier whenDepositsNotPaused() {
        if (depositsPaused) revert YZ_DepositsPaused();
        _;
    }

    modifier whenRedemptionsNotPaused() {
        if (redemptionsPaused) revert YZ_RedemptionsPaused();
        _;
    }

    // ======== Core Override: _depositAndSend ========

    /**
     * @notice Override _depositAndSend to add enforcement BEFORE vault deposit
     * @dev This is the CORRECT extension point - called from handleCompose() -> _depositAndSend()
     * @dev Enforcement reverts are caught by VaultComposerSync's try-catch around handleCompose()
     * @dev This means _refund() is triggered automatically on enforcement failure
     * @dev Slippage is handled by parent _assertSlippage() after deposit
     * @dev msg.value ENFORCEMENT: VaultComposerSync.lzCompose() forwards
     *      msg.value as _msgValue. If insufficient for OFT _send(), the
     *      revert is caught by try-catch → _refund() is triggered automatically.
     *      No additional enforcement needed per Integration Checklist.
     *
     * @param _depositor The depositor (bytes32 format for non-evm compatibility)
     * @param _assetAmount The number of assets to deposit (may be truncated by sharedDecimals)
     * @param _sendParam Parameter that defines how to send the shares
     * @param _refundAddress Address to receive excess payment
     * @param _msgValue The amount of native tokens sent
     */
    function _depositAndSend(
        bytes32 _depositor,
        uint256 _assetAmount,
        SendParam memory _sendParam,
        address _refundAddress,
        uint256 _msgValue
    ) internal virtual override whenDepositsNotPaused {
        // Convert bytes32 to address for enforcement
        address depositorAddr = _depositor.bytes32ToAddress();

        // ====== 1: Enforce Whitelist (if enabled) ======
        if (whitelistEnabled) {
            if (!whitelist[depositorAddr]) {
                revert YZ_NotWhitelisted(depositorAddr);
            }
        }

        // ====== 2: Enforce TVL Cap ======
        // Note: _assetAmount may be truncated by sharedDecimals, but this is conservative
        // Actual deposit amount could be slightly less, but we enforce on the requested amount
        if (tvlCap > 0) {
            uint256 currentTVL = VAULT.totalAssets();
            if (currentTVL + _assetAmount > tvlCap) {
                revert YZ_TVLCapExceeded(currentTVL, _assetAmount, tvlCap);
            }
        }

        // ====== 3: Enforce User Deposit Cap ======
        if (userDepositCap[depositorAddr] > 0) {
            uint256 currentDeposit = userDeposits[depositorAddr];
            if (currentDeposit + _assetAmount > userDepositCap[depositorAddr]) {
                revert YZ_UserCapExceeded(depositorAddr, currentDeposit, _assetAmount, userDepositCap[depositorAddr]);
            }
        }

        // ====== 4: Check Vault Deposit Capacity ======
        // Defensive check: ensure vault can accept this deposit
        uint256 maxDeposit = VAULT.maxDeposit(address(this));
        if (_assetAmount > maxDeposit) {
            revert ERC4626.ERC4626ExceededMaxDeposit(address(this), _assetAmount, maxDeposit);
        }

        // ====== 5: Record TVL before deposit ======
        uint256 tvlBefore = VAULT.totalAssets();

        // ====== 6: Call parent _depositAndSend ======
        // This executes: _deposit() -> _assertSlippage() -> _send()
        // If any step fails, entire transaction reverts (including our checks above)
        // VaultComposerSync's try-catch will catch the revert and call _refund()
        super._depositAndSend(_depositor, _assetAmount, _sendParam, _refundAddress, _msgValue);

        // ====== 7: Update User Deposit Tracking (after success) ======
        // Update with actual TVL increase (may differ due to vault rounding, strategy yield, etc.)
        uint256 tvlAfter = VAULT.totalAssets();
        uint256 actualTvlIncrease = tvlAfter > tvlBefore ? tvlAfter - tvlBefore : _assetAmount;
        userDeposits[depositorAddr] += actualTvlIncrease;

        emit EnforcementExecuted(depositorAddr, actualTvlIncrease, tvlBefore, tvlAfter);
    }

    // ======== Core Override: _redeemAndSend ========

    /**
     * @notice Override _redeemAndSend to update tracking on redemption
     * @dev REPLICATED from VaultComposerSync (ovault-evm@1.0.0)
     *      Parent flow: _redeem() -> _assertSlippage() -> _send()
     *      We replicate to insert tracking between _redeem() and _send().
     *      MUST be reviewed on any ovault-evm version upgrade.
     * @dev Assets are sent OUT after _redeem(), so we must track BEFORE _send()
     * @dev msg.value ENFORCEMENT: VaultComposerSync.lzCompose() passes msg.value
     *      as _msgValue to _depositAndSend/_redeemAndSend. If insufficient for the
     *      OFT _send(), the revert is caught by try-catch → _refund() is triggered.
     *      No additional enforcement needed per Integration Checklist guidance.
     *
     * @param _redeemer The redeemer (bytes32 format for non-evm compatibility)
     * @param _shareAmount The number of shares to redeem
     * @param _sendParam Parameter that defines how to send the assets
     * @param _refundAddress Address to receive excess payment
     * @param _msgValue The amount of native tokens sent
     */
    function _redeemAndSend(
        bytes32 _redeemer,
        uint256 _shareAmount,
        SendParam memory _sendParam,
        address _refundAddress,
        uint256 _msgValue
    ) internal virtual override whenRedemptionsNotPaused {
        // Convert bytes32 to address
        address redeemerAddr = _redeemer.bytes32ToAddress();

        // ====== 1: Record balance before redeem ======
        uint256 preAssetBalance = IERC20(ASSET_ERC20).balanceOf(address(this));

        // ====== 2: Redeem shares for assets ======
        _redeem(_redeemer, _shareAmount);
        
        // ====== 3: Calculate assets received ======
        uint256 postAssetBalance = IERC20(ASSET_ERC20).balanceOf(address(this));
        uint256 assetAmountReceived = postAssetBalance - preAssetBalance;

        // ====== 4: Assert slippage ======
        _assertSlippage(assetAmountReceived, _sendParam.minAmountLD);

        // ======  5: Reset minAmountLD to 0 ======
        // Slippage already verified above against user's requested minimum.
        // Setting to 0 prevents OFT from applying additional slippage checks
        // during _send(), since we've already validated the received amount.
        _sendParam.amountLD = assetAmountReceived;
        _sendParam.minAmountLD = 0;

        // ====== 6: Update tracking BEFORE send (assets about to leave) ======
        // Underflow protection: if user received more assets than tracked (due to yield),
        // reset to 0 and emit tracking reset event for monitoring
        if (userDeposits[redeemerAddr] >= assetAmountReceived) {
            userDeposits[redeemerAddr] -= assetAmountReceived;
        } else {
            emit UserDepositTrackingReset(redeemerAddr, userDeposits[redeemerAddr], assetAmountReceived);
            userDeposits[redeemerAddr] = 0;
        }

        // ====== 7: Send assets cross-chain ======
        _send(ASSET_OFT, _sendParam, _refundAddress, _msgValue);

        emit Redeemed(_redeemer, _sendParam.to, _sendParam.dstEid, _shareAmount, assetAmountReceived);
    }

    // ======== Configuration Functions ========

    /**
     * @notice Set TVL cap
     * @param _tvlCap New TVL cap (0 = unlimited)
     */
    function setTVLCap(uint256 _tvlCap) external onlyAdmin {
        uint256 oldCap = tvlCap;
        tvlCap = _tvlCap;
        emit TVLCapUpdated(oldCap, _tvlCap);
    }

    /**
     * @notice Set per-user deposit cap
     * @param _user User address
     * @param _cap New cap (0 = unlimited)
     */
    function setUserCap(address _user, uint256 _cap) external onlyAdmin {
        if (_user == address(0)) revert YZ_ZeroAddress();
        uint256 oldCap = userDepositCap[_user];
        userDepositCap[_user] = _cap;
        emit UserCapUpdated(_user, oldCap, _cap);
    }

    /**
     * @notice Batch set user caps
     * @param _users User addresses
     * @param _caps Caps for each user
     */
    function batchSetUserCaps(address[] calldata _users, uint256[] calldata _caps) external onlyAdmin {
        require(_users.length == _caps.length, "Length mismatch");
        for (uint256 i = 0; i < _users.length; i++) {
            uint256 oldCap = userDepositCap[_users[i]];
            userDepositCap[_users[i]] = _caps[i];
            emit UserCapUpdated(_users[i], oldCap, _caps[i]);
        }
    }

    /**
     * @notice Pause deposits only (redemptions remain open)
     * @dev This is the recommended pause action for risk mitigation
     */
    function pauseDeposits() external onlyAdmin {
        depositsPaused = true;
        emit DepositsPaused(msg.sender);
    }

    /**
     * @notice Unpause deposits
     */
    function unpauseDeposits() external onlyAdmin {
        depositsPaused = false;
        emit DepositsUnpaused(msg.sender);
    }

    /**
     * @notice Pause redemptions (USE WITH EXTREME CAUTION)
     * @dev Pausing redemptions blocks user fund access - only use in emergencies
     */
    function pauseRedemptions() external onlyAdmin {
        redemptionsPaused = true;
        emit RedemptionsPaused(msg.sender);
    }

    /**
     * @notice Unpause redemptions
     */
    function unpauseRedemptions() external onlyAdmin {
        redemptionsPaused = false;
        emit RedemptionsUnpaused(msg.sender);
    }

    /**
     * @notice Pause all operations (deposits and redemptions)
     * @dev Convenience function for emergency shutdown
     */
    function pauseAll() external onlyAdmin {
        depositsPaused = true;
        redemptionsPaused = true;
        emit DepositsPaused(msg.sender);
        emit RedemptionsPaused(msg.sender);
    }

    /**
     * @notice Unpause all operations
     */
    function unpauseAll() external onlyAdmin {
        depositsPaused = false;
        redemptionsPaused = false;
        emit DepositsUnpaused(msg.sender);
        emit RedemptionsUnpaused(msg.sender);
    }

    /**
     * @notice Enable/disable whitelist mode
     * @param _enabled Whether whitelist is enabled
     */
    function setWhitelistEnabled(bool _enabled) external onlyAdmin {
        whitelistEnabled = _enabled;
        emit WhitelistEnabled(_enabled);
    }

    /**
     * @notice Set whitelist status for address
     * @param _user User address
     * @param _status Whitelist status
     */
    function setWhitelist(address _user, bool _status) external onlyAdmin {
        if (_user == address(0)) revert YZ_ZeroAddress();
        whitelist[_user] = _status;
        emit WhitelistUpdated(_user, _status);
    }

    /**
     * @notice Batch set whitelist status
     * @param _users User addresses
     * @param _statuses Status for each user
     */
    function batchSetWhitelist(address[] calldata _users, bool[] calldata _statuses) external onlyAdmin {
        require(_users.length == _statuses.length, "Length mismatch");
        for (uint256 i = 0; i < _users.length; i++) {
            whitelist[_users[i]] = _statuses[i];
            emit WhitelistUpdated(_users[i], _statuses[i]);
        }
    }

    /**
     * @notice Transfer admin role
     * @param _newAdmin New admin address
     */
    function setAdmin(address _newAdmin) external onlyAdmin {
        if (_newAdmin == address(0)) revert YZ_ZeroAddress();
        address oldAdmin = admin;
        admin = _newAdmin;
        emit AdminUpdated(oldAdmin, _newAdmin);
    }

    // ======== View Functions ========

    /**
     * @notice Get total value locked (from vault, includes strategy yield)
     * @return uint256 TVL
     */
    function getTotalValueLocked() external view returns (uint256) {
        return VAULT.totalAssets();
    }

    /**
     * @notice Get user's shares balance
     * @param _user User address
     * @return uint256 Shares balance
     */
    function getUserShares(address _user) external view returns (uint256) {
        return IERC20(SHARE_ERC20).balanceOf(_user);
    }

    /**
     * @notice Get user's assets value
     * @param _user User address
     * @return uint256 Assets value
     */
    function getUserAssets(address _user) external view returns (uint256) {
        uint256 shares = IERC20(SHARE_ERC20).balanceOf(_user);
        return VAULT.convertToAssets(shares);
    }

    /**
     * @notice Get user deposit tracking info
     * @param _user User address
     * @return deposit Tracked deposit amount
     * @return cap User's deposit cap
     * @return remaining Remaining capacity
     */
    function getUserDepositInfo(address _user) external view returns (
        uint256 deposit,
        uint256 cap,
        uint256 remaining
    ) {
        deposit = userDeposits[_user];
        cap = userDepositCap[_user];
        if (cap > 0) {
            remaining = cap > deposit ? cap - deposit : 0;
        } else {
            remaining = type(uint256).max;
        }
    }

    /**
     * @notice Check if deposit would exceed caps
     * @param _user User address
     * @param _amount Deposit amount
     * @return allowed Whether deposit is allowed
     * @return reason Reason if not allowed
     */
    function canDeposit(address _user, uint256 _amount) external view returns (
        bool allowed,
        string memory reason
    ) {
        if (depositsPaused) return (false, "Deposits paused");
        
        if (whitelistEnabled && !whitelist[_user]) {
            return (false, "Not whitelisted");
        }
        
        if (tvlCap > 0) {
            uint256 currentTVL = VAULT.totalAssets();
            if (currentTVL + _amount > tvlCap) {
                return (false, "TVL cap exceeded");
            }
        }
        
        if (userDepositCap[_user] > 0) {
            uint256 currentDeposit = userDeposits[_user];
            if (currentDeposit + _amount > userDepositCap[_user]) {
                return (false, "User cap exceeded");
            }
        }
        
        return (true, "");
    }

    // ======== Emergency Functions ========
    // NOTE: This does NOT restrict LayerZero native refund/retry (permissionless)

    /**
     * @notice Emergency withdraw of stuck assets
     * @dev Only for assets stuck in this contract, does NOT affect LayerZero recovery
     * @param _amount Amount to withdraw
     * @param _to Recipient
     */
    function emergencyWithdraw(uint256 _amount, address _to) external onlyAdmin {
        if (_to == address(0)) revert YZ_ZeroAddress();
        require(_amount > 0, "Zero amount");

        uint256 balance = IERC20(ASSET_ERC20).balanceOf(address(this));
        require(_amount <= balance, "Insufficient balance");

        IERC20(ASSET_ERC20).safeTransfer(_to, _amount);
    }

    /**
     * @notice Emergency withdraw of stuck share tokens
     * @dev Only for shares stuck in this contract, does NOT affect LayerZero recovery
     * @param _amount Amount to withdraw
     * @param _to Recipient
     */
    function emergencyWithdrawShares(uint256 _amount, address _to) external onlyAdmin {
        if (_to == address(0)) revert YZ_ZeroAddress();
        require(_amount > 0, "Zero amount");

        uint256 balance = IERC20(SHARE_ERC20).balanceOf(address(this));
        require(_amount <= balance, "Insufficient balance");

        IERC20(SHARE_ERC20).safeTransfer(_to, _amount);
    }

    /**
     * @notice Emergency withdraw of stuck native ETH
     * @dev Only for ETH stuck in this contract (eg, failed sends, accidental transfers)
     * @param _amount Amount to withdraw
     * @param _to Recipient
     */
    function emergencyWithdrawNative(uint256 _amount, address payable _to) external onlyAdmin {
        if (_to == address(0)) revert YZ_ZeroAddress();
        require(_amount > 0, "Zero amount");
        require(address(this).balance >= _amount, "Insufficient balance");

        (bool success, ) = _to.call{ value: _amount }("");
        require(success, "Native transfer failed");
    }

    // ======== Test Helpers ========
    // NOTE: These functions are for testing only and should be remove

    /**
     * @notice Test helper to set user deposit tracking directly
     * @dev Only for testing, should be removed in production
     */
    function exposed_setUserDeposit(address _user, uint256 _amount) external onlyAdmin {
        userDeposits[_user] = _amount;
    }

    receive() external payable {}
}