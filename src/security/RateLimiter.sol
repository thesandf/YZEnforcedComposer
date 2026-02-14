// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
/// @title RateLimiter
/// @notice Rate limiting for vault operations in the YieldZero Ops SDK.
/// 
/// This contract provides rate limiting functionality to prevent
/// excessive deposits/withdrawals within a time window, protecting
/// against flash loan attacks and sudden TVL changes.
contract RateLimiter is AccessControl {
    /// Window size in seconds
    uint256 private _windowSize;
    
    /// Maximum actions per window
    uint256 private _maxActionsPerWindow;
    
    /// Current window start
    uint256 private _windowStart;
    
    /// Actions in current window
    uint256 private _actionsInWindow;
    
    /// Rate limit config per user
    mapping(address => UserRateLimit) private _userRateLimits;
    struct UserRateLimit {
        uint256 windowStart;
        uint256 actionsInWindow;
        uint256 lastActionTime;
    }
    event RateLimitUpdated(uint256 windowSize, uint256 maxActions);
    event ActionRateLimited(address indexed user, string actionType);
    event UserRateLimitSet(address indexed user, uint256 maxActions);
    bytes32 public constant RATE_LIMIT_ADMIN_ROLE = keccak256("RATE_LIMIT_ADMIN_ROLE");
    modifier onlyRateLimitAdmin() {
        require(hasRole(RATE_LIMIT_ADMIN_ROLE, msg.sender), "RateLimiter: caller is not rate limit admin");
        _;
    }
    /// @notice Constructor
    constructor(uint256 windowSize_, uint256 maxActions_) {
        require(windowSize_ > 0, "RateLimiter: window size must be > 0");
        require(maxActions_ > 0, "RateLimiter: max actions must be > 0");
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(RATE_LIMIT_ADMIN_ROLE, msg.sender);
        
        _windowSize = windowSize_;
        _maxActionsPerWindow = maxActions_;
        _windowStart = block.timestamp;
        _actionsInWindow = 0;
    }
    /// @notice Update rate limit parameters
    function updateRateLimit(uint256 windowSize_, uint256 maxActions_) 
        external 
        onlyRateLimitAdmin 
    {
        require(windowSize_ > 0, "RateLimiter: window size must be > 0");
        require(maxActions_ > 0, "RateLimiter: max actions must be > 0");
        
        _windowSize = windowSize_;
        _maxActionsPerWindow = maxActions_;
        
        emit RateLimitUpdated(windowSize_, maxActions_);
    }
    /// @notice Set per-user rate limit
    function setUserRateLimit(address _user, uint256 maxActions_) 
        external 
        onlyRateLimitAdmin 
    {
        require(_user != address(0), "RateLimiter: zero address");
        
        _userRateLimits[_user] = UserRateLimit({
            windowStart: block.timestamp,
            actionsInWindow: 0,
            lastActionTime: 0
        });
        
        emit UserRateLimitSet(_user, maxActions_);
    }
    /// @notice Check and update rate limit for an action
    /// @return True if action is allowed
    function checkAndUpdateRateLimit(address _user) 
        external 
        returns (bool) 
    {
        /// Check if we're in a new window
        if (block.timestamp >= _windowStart + _windowSize) {
            /// Reset window
            _windowStart = block.timestamp;
            _actionsInWindow = 0;
        }
        
        /// Check global rate limit
        require(_actionsInWindow < _maxActionsPerWindow, "RateLimiter: global rate limit exceeded");
        
        /// Check user-specific rate limit
        UserRateLimit storage userLimit = _userRateLimits[_user];
        if (userLimit.windowStart > 0) {
            /// User has custom limit - check it
            if (block.timestamp >= userLimit.windowStart + _windowSize) {
                /// Reset user window
                userLimit.windowStart = block.timestamp;
                userLimit.actionsInWindow = 0;
            }
        }
        
        /// Update counters
        _actionsInWindow++;
        userLimit.actionsInWindow++;
        userLimit.lastActionTime = block.timestamp;
        
        return true;
    }
    /// @notice Get current rate limit status
    /// @return windowStart Current window start timestamp
    /// @return actionsUsed Number of actions used in current window
    /// @return maxActions Maximum actions allowed per window
    function getRateLimitStatus() 
        external 
        view 
        returns (uint256 windowStart, uint256 actionsUsed, uint256 maxActions) 
    {
        return (_windowStart, _actionsInWindow, _maxActionsPerWindow);
    }
    /// @notice Get user rate limit status
    /// @return windowStart User's window start timestamp
    /// @return actionsUsed User's actions used in current window
    /// @return lastActionTime User's last action timestamp
    function getUserRateLimitStatus(address _user) 
        external 
        view 
        returns (uint256 windowStart, uint256 actionsUsed, uint256 lastActionTime) 
    {
        UserRateLimit storage userLimit = _userRateLimits[_user];
        return (userLimit.windowStart, userLimit.actionsInWindow, userLimit.lastActionTime);
    }
    function windowSize() external view returns (uint256) {
        return _windowSize;
    }
    function maxActionsPerWindow() external view returns (uint256) {
        return _maxActionsPerWindow;
    }
    /// @notice Check if a user can operate (for compatibility with existing code)
    /// @return True if user can operate
    function canOperate(address _user) external view returns (bool) {
        /// For now, always allow operations
        return true;
    }
    /// @notice Record an operation for rate limiting
    function recordOperation(address _user) external {
        /// Check if we're in a new window
        if (block.timestamp >= _windowStart + _windowSize) {
            _windowStart = block.timestamp;
            _actionsInWindow = 0;
        }
        
        /// Check global rate limit
        if (_actionsInWindow >= _maxActionsPerWindow) {
            revert("RateLimiter: global rate limit exceeded");
        }
        
        /// Update counters
        _actionsInWindow++;
        
        UserRateLimit storage userLimit = _userRateLimits[_user];
        userLimit.actionsInWindow++;
        userLimit.lastActionTime = block.timestamp;
    }
}
