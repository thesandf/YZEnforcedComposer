// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {YieldZeroMessager} from "./YieldZeroMessager.sol";
import {YieldZeroComposer} from "./YieldZeroComposer.sol";
import {YieldZeroVault} from "../core/YieldZeroVault.sol";
import {
    YZHub_InvalidVault,
    YZHub_InvalidComposer,
    YZHub_InvalidMessager,
    YZHub_MessagerNotConfigured,
    YZHub_Paused,
    YZHub_MaxSpokesExceeded,
    YZHub_InvalidSpoke,
    YZHub_SpokeAlreadyConnected,
    YZHub_SpokeNotConnected,
    YZHub_InvalidFeeBps,
    YZHub_InvalidFeeRecipient,
    YZHub_HarvestDisabled,
    YZHub_HarvestNotReady,
    YZHub_NoSpokesConnected,
    YZHub_CallerNotFeeRecipient,
    YZHub_NoFeesToWithdraw,
    YZHub_NativeTransferFailed
} from "../errors/Errors.sol";

/**
 *
 * @title YieldZeroHub
 * @notice Central hub contract managing cross-chain state and coordination
 * @dev This contract orchestrates the hub-side logic for the omnichain vault
 */

contract YieldZeroHub is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Maximum connected spokes to prevent DoS
    uint256 public constant MAX_CONNECTED_SPOKES = 50;

    /// @notice The vault contract
    address public vault;
    /// @notice The composer contract
    address public composer;
    /// @notice The messager contract for cross-chain communication
    address payable public messager;

    /// @notice Connected spokes (eid => spoke address)
    mapping(uint32 eid => address spoke) public connectedSpokes;

    uint32[] private connectedEids;
    /// @notice Track if EID is in array to prevent duplicates
    mapping(uint32 => bool) private isEidConnected;

    /// @notice Whether hub is paused
    bool public isPaused;
    /// @notice Fee basis points (e.g 100 = 1%)
    uint256 public feeBasisPoints = 100; // 1% default
    /// @notice Fee recipient
    address public feeRecipient;
    /// @notice Total fees collected
    uint256 public totalFeesCollected;
    /// @notice Cross-chain harvest enabled
    bool public harvestEnabled = true;
    /// @notice Last harvest timestamp
    uint256 public lastHarvestTime;
    /// @notice Harvest interval (e.g 7 days)
    uint256 public constant HARVEST_INTERVAL = 7 days;

    event SpokeConnected(uint32 indexed eid, address spoke);
    event SpokeDisconnected(uint32 indexed eid);
    event VaultUpdated(address newVault);
    event ComposerUpdated(address newComposer);
    event HubPaused(bool indexed paused);
    event FeeUpdated(uint256 newFeeBasisPoints);
    event FeeRecipientUpdated(address newRecipient);
    event HarvestTriggered(uint256 yieldAmount);
    event FeesCollected(uint256 amount);
    event MessagerUpdated(address newMessager);
    event CrossChainDistributionInitiated(uint32 indexed eid, uint256 yieldAmount);
    event StateSyncInitiated(uint32 indexed eid, uint256 tvl, uint256 totalSupply, uint256 yieldAccumulated);

    modifier whenNotPaused() {
        if (isPaused) {
            revert YZHub_Paused();
        }
        _;
    }

    /**
     * @notice Initialize the hub
     */

    constructor(address _vault, address _composer, address _feeRecipient, address _owner) Ownable(_owner) {
        if (_vault == address(0)) {
            revert YZHub_InvalidVault();
        }
        if (_composer == address(0)) {
            revert YZHub_InvalidComposer();
        }
        if (_feeRecipient == address(0)) {
            revert YZHub_InvalidFeeRecipient();
        }
        vault = _vault;
        composer = _composer;
        feeRecipient = _feeRecipient;
    }

    /**
     *
     * @notice Connect a spoke chain
     * @dev Only owner can connect spokes
     */

    function connectSpoke(uint32 _eid, address _spoke) external onlyOwner {
        if (_spoke == address(0)) {
            revert YZHub_InvalidSpoke();
        }
        if (connectedEids.length >= MAX_CONNECTED_SPOKES) {
            revert YZHub_MaxSpokesExceeded();
        }
        if (isEidConnected[_eid]) {
            revert YZHub_SpokeAlreadyConnected();
        }

        connectedSpokes[_eid] = _spoke;
        connectedEids.push(_eid);
        isEidConnected[_eid] = true;

        emit SpokeConnected(_eid, _spoke);
    }

    /**
     * @notice Disconnect a spoke chain
     */

    function disconnectSpoke(uint32 _eid) external onlyOwner {
        if (!isEidConnected[_eid]) {
            revert YZHub_SpokeNotConnected();
        }

        delete connectedSpokes[_eid];
        isEidConnected[_eid] = false;

        // Remove from array
        for (uint256 i = 0; i < connectedEids.length; i++) {
            if (connectedEids[i] == _eid) {
                connectedEids[i] = connectedEids[connectedEids.length - 1];
                connectedEids.pop();
                break;
            }
        }

        emit SpokeDisconnected(_eid);
    }

    /**
     * @notice Check if a spoke is connected
     */

    function isSpokeConnected(uint32 _eid) external view returns (bool connected) {
        return connectedSpokes[_eid] != address(0);
    }

    /**
     * @notice Update vault address
     */

    function setVault(address _newVault) external onlyOwner {
        if (_newVault == address(0)) {
            revert YZHub_InvalidVault();
        }
        vault = _newVault;
        emit VaultUpdated(_newVault);
    }

    /**
     * @notice Update composer address
     */

    function setComposer(address _newComposer) external onlyOwner {
        if (_newComposer == address(0)) {
            revert YZHub_InvalidComposer();
        }
        composer = _newComposer;
        emit ComposerUpdated(_newComposer);
    }

    /**
     * @notice Update messager address
     */

    function setMessager(address payable _newMessager) external onlyOwner {
        if (_newMessager == address(0)) {
            revert YZHub_InvalidMessager();
        }
        messager = _newMessager;
        emit MessagerUpdated(_newMessager);
    }

    /**
     * @notice Pause/unpause hub operations
     */

    function setPaused(bool _paused) external onlyOwner {
        isPaused = _paused;
        emit HubPaused(_paused);
    }

    /**
     * @notice Update fee configuration
     */

    function setFeeBasisPoints(uint256 _newFeeBasisPoints) external onlyOwner {
        if (_newFeeBasisPoints > 10000) {
            revert YZHub_InvalidFeeBps();
        }
        feeBasisPoints = _newFeeBasisPoints;
        emit FeeUpdated(_newFeeBasisPoints);
    }

    /**
     * @notice Update fee recipient
     */

    function setFeeRecipient(address _newRecipient) external onlyOwner {
        if (_newRecipient == address(0)) {
            revert YZHub_InvalidFeeRecipient();
        }
        feeRecipient = _newRecipient;
        emit FeeRecipientUpdated(_newRecipient);
    }

    /**
     * @notice Trigger cross-chain harvest
     */

    function triggerHarvest(uint256 _yieldAmount) external onlyOwner whenNotPaused {
        if (_yieldAmount == 0) {
            revert YZHub_HarvestNotReady();
        }
        if (block.timestamp < lastHarvestTime + HARVEST_INTERVAL) {
            revert YZHub_HarvestNotReady();
        }
        if (!harvestEnabled) {
            revert YZHub_HarvestDisabled();
        }
        // Calculate fee
        uint256 fee = (_yieldAmount * feeBasisPoints) / 10000;
        uint256 netYield = _yieldAmount - fee;

        // Record fee
        totalFeesCollected += fee;

        // Distribute yield via YieldZeroMessager
        if (messager != address(0)) {
            _distributeYieldToSpokes(netYield);
        }

        emit HarvestTriggered(netYield);
        emit FeesCollected(fee);

        lastHarvestTime = block.timestamp;
    }

    /**
     * @notice Distribute yield to all connected spokes
     */

    function _distributeYieldToSpokes(uint256 _netYield) internal {
        if (_netYield == 0) {
            revert YZHub_HarvestNotReady();
        }

        if (messager == address(0)) {
            revert YZHub_InvalidMessager();
        }

        YieldZeroMessager messagerContract = YieldZeroMessager(payable(messager));
        uint256 connectedCount = connectedEids.length;

        if (connectedCount == 0) {
            revert YZHub_NoSpokesConnected();
        }

        // Send harvest distribution to all connected spokes
        uint256 spokeYield = _netYield / connectedCount;
        uint256 totalDistributed = 0;

        for (uint256 i = 0; i < connectedEids.length; i++) {
            uint32 eid = connectedEids[i];
            // Send native fee with the message (0.3 ether to cover the required fee)
            messagerContract.sendHarvestDistribution{value: 300000000000000000}(eid, spokeYield);
            emit CrossChainDistributionInitiated(eid, spokeYield);
            totalDistributed += spokeYield;
        }

        // Handle remainder (due to integer division)
        uint256 remainder = _netYield - totalDistributed;

        if (remainder > 0 && connectedEids.length > 0) {
            // Distribute remainder to first spoke
            messagerContract.sendHarvestDistribution{value: 300000000000000000}(connectedEids[0], remainder);
            emit CrossChainDistributionInitiated(connectedEids[0], remainder);
        }
    }

    /**
     * @notice Get number of connected spokes
     */

    function _getConnectedSpokeCount() internal view returns (uint256 count) {
        return connectedEids.length;
    }

    /**
     * @notice Get all connected spoke endpoint IDs
     */

    function getConnectedSpokeEids() external view returns (uint32[] memory eids) {
        eids = new uint32[](connectedEids.length);
        for (uint256 i = 0; i < connectedEids.length; i++) {
            eids[i] = connectedEids[i];
        }
    }

    /**
     * @notice Send emergency stop to all spokes
     */

    function triggerEmergencyStop() external onlyOwner nonReentrant {
        if (messager == address(0)) {
            revert YZHub_MessagerNotConfigured();
        }

        YieldZeroMessager messagerContract = YieldZeroMessager(payable(messager));
        messagerContract.sendEmergencyStop();
        isPaused = true;

        emit HubPaused(true);
    }

    /**
     * @notice Initiate cross-chain state sync
     */

    function syncStateToSpokes() external onlyOwner {
        if (messager == address(0)) {
            revert YZHub_MessagerNotConfigured();
        }

        YieldZeroComposer composerContract = YieldZeroComposer(composer);
        YieldZeroVault vaultContract = YieldZeroVault(vault);
        uint256 tvl = composerContract.getTotalValueLocked();
        uint256 totalSupply = vaultContract.totalSupply();
        uint256 yieldAccumulated = vaultContract.totalYieldAccumulated();
        YieldZeroMessager messagerContract = YieldZeroMessager(payable(messager));

        messagerContract.sendStateSync(tvl, totalSupply, yieldAccumulated);

        // Also send individual state sync to each spoke
        for (uint256 i = 0; i < connectedEids.length; i++) {
            emit StateSyncInitiated(connectedEids[i], tvl, totalSupply, yieldAccumulated);
        }
    }

    /**
     * @notice Withdraw collected fees
     */

    function withdrawFees(address _token) external nonReentrant {
        if (_token != address(0) && IERC20(_token).balanceOf(address(this)) == 0) {
            revert YZHub_NoFeesToWithdraw();
        }

        if (msg.sender != feeRecipient) {
            revert YZHub_CallerNotFeeRecipient();
        }

        if (_token == address(0)) {
            // Withdraw Native token
            uint256 balance = address(this).balance;
            (bool success,) = feeRecipient.call{value: balance}("");
            if (!success) {
                revert YZHub_NativeTransferFailed();
            }
        } else {
            // Withdraw ERC20
            uint256 balance = IERC20(_token).balanceOf(address(this));
            IERC20(_token).safeTransfer(feeRecipient, balance);
        }
    }

    /**
     * @notice Enable/disable harvesting
     */

    function setHarvestEnabled(bool _enabled) external onlyOwner {
        harvestEnabled = _enabled;
    }

    /**
     * @notice Get hub status
     */

    function getHubStatus()
        external
        view
        returns (address vaultAddr, address composerAddr, bool paused, uint256 fee, uint256 tvl)
    {
        uint256 calculatedTvl = 0;
        if (composer != address(0)) {
            calculatedTvl = YieldZeroComposer(composer).getTotalValueLocked();
        }
        return (vault, composer, isPaused, feeBasisPoints, calculatedTvl);
    }

    /**
     * @notice Get complete vault stats
     *
     */

    function getVaultStats()
        external
        view
        returns (uint256 totalAssets, uint256 totalSupply, uint256 totalYield, uint256 tvl)
    {
        YieldZeroVault vaultContract = YieldZeroVault(vault);
        (totalAssets, totalSupply, totalYield) = vaultContract.getVaultStats();

        tvl = YieldZeroComposer(composer).getTotalValueLocked();

        return (totalAssets, totalSupply, totalYield, tvl);
    }

    /// @notice Receive ETH

    receive() external payable {}
}
