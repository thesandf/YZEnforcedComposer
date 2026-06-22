// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {YZRateLimiter_OperationLimitExceeded, YZRateLimiter_InvalidLimit} from "../errors/Errors.sol";

/**
 * @title RateLimiter
 * @notice Enforces per-user operation limits to prevent abuse
 * @dev Protects against DoS attacks and excessive cross-chain operations
 * - Can be applied per-user, per-chain, or globally
 */
contract RateLimiter is Ownable {
    /// @notice Time window for rate limiting (1 hour)
    uint256 public constant RATE_LIMIT_WINDOW = 1 hours;

    /// @notice Maximum operations per user per window
    uint256 public maxOperationsPerWindow;

    /// @notice Tracks the count of operations per user in current window
    mapping(address user => mapping(uint256 window => uint256 count)) public operationCount;

    /// @notice Tracks when a user last performed an action
    mapping(address user => uint256 timestamp) public lastOperationTime;

    /// @notice Tracks authorized caller addresses (e.g. Composer contracts)
    mapping(address => bool) public authorizedCallers;

    error UnauthorizedCaller();

    event RateLimitUpdated(uint256 newLimit);
    event OperationLimited(address indexed user, uint256 timestamp);
    event OperationRecorded(address indexed user, uint256 count, uint256 window);
    event AuthorizedCallerUpdated(address indexed caller, bool status);

    modifier onlyAuthorized() {
        if (!authorizedCallers[msg.sender]) revert UnauthorizedCaller();
        _;
    }

    constructor(uint256 _maxOperationsPerWindow, address _owner) Ownable(_owner) {
        if (_maxOperationsPerWindow == 0) revert YZRateLimiter_InvalidLimit();
        maxOperationsPerWindow = _maxOperationsPerWindow;
    }

    /**
     * @notice Set caller authorization status (owner only)
     */
    function setAuthorizedCaller(address caller, bool status) external onlyOwner {
        authorizedCallers[caller] = status;
        emit AuthorizedCallerUpdated(caller, status);
    }

    /**
     * @notice Check if user has exceeded rate limit
     */
    function canOperate(address user) external view returns (bool allowed) {
        uint256 currentWindow = block.timestamp / RATE_LIMIT_WINDOW;
        uint256 count = operationCount[user][currentWindow];
        return count < maxOperationsPerWindow;
    }

    /**
     * @notice Record an operation for a user
     * @dev Should be called by vault/composer after validating the operation
     */
    function recordOperation(address user) external onlyAuthorized {
        uint256 currentWindow = block.timestamp / RATE_LIMIT_WINDOW;
        uint256 count = operationCount[user][currentWindow];

        if (count >= maxOperationsPerWindow) revert YZRateLimiter_OperationLimitExceeded();

        operationCount[user][currentWindow] = count + 1;
        lastOperationTime[user] = block.timestamp;

        emit OperationRecorded(user, count + 1, currentWindow);
    }

    /**
     * @notice Get remaining operations for user in current window
     */
    function remainingOperations(address user) external view returns (uint256 remaining) {
        uint256 currentWindow = block.timestamp / RATE_LIMIT_WINDOW;
        uint256 count = operationCount[user][currentWindow];

        if (count >= maxOperationsPerWindow) {
            return 0;
        }
        return maxOperationsPerWindow - count;
    }

    /**
     * @notice Update the rate limit (admin only)
     */
    function updateRateLimit(uint256 _newLimit) external onlyOwner {
        if (_newLimit == 0) revert YZRateLimiter_InvalidLimit();
        maxOperationsPerWindow = _newLimit;
        emit RateLimitUpdated(_newLimit);
    }
}
