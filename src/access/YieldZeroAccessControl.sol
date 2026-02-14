// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {
    YZAccessControl_CallerNotAdmin,
    YZAccessControl_RoleAlreadyGranted,
    YZAccessControl_RoleNotGranted,
    YZAccessControl_ZeroAddress
} from "../errors/Errors.sol";
/// @title YieldZeroAccessControl
/// @notice Centralized RBAC management for YieldZero protocol
/// @dev Defines 4 distinct roles with clear responsibilities
contract YieldZeroAccessControl is AccessControl {
    /// @notice Admin role: Can manage roles, pause protocol, set critical parameters
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    /// @notice Config Manager role: Can update fees, timelock delay, rate limits
    bytes32 public constant CONFIG_MANAGER_ROLE = keccak256("CONFIG_MANAGER_ROLE");
    /// @notice Harvester role: Can trigger harvests and distribute yield
    bytes32 public constant HARVESTER_ROLE = keccak256("HARVESTER_ROLE");
    ////@notice Emergency role: Can pause protocol and trigger emergency withdrawals
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
    function _preGrant(bytes32 role, address account) internal view {
        if (account == address(0)) revert YZAccessControl_ZeroAddress();
        if (hasRole(role, account)) revert YZAccessControl_RoleAlreadyGranted();
    }
    function _preRevoke(bytes32 role, address account) internal view {
        if (account == address(0)) revert YZAccessControl_ZeroAddress();
        if (!hasRole(role, account)) revert YZAccessControl_RoleNotGranted();
        if (account == msg.sender && role == ADMIN_ROLE) {
            revert YZAccessControl_CallerNotAdmin();
        }
    }
    event RoleGrantedWithReason(bytes32 indexed role, address indexed account, address indexed granter, string reason);
    event RoleRevokedWithReason(bytes32 indexed role, address indexed account, address indexed revoker, string reason);
    /// @notice Initialize with default admin
    constructor(address _defaultAdmin) {
        if (_defaultAdmin == address(0)) revert YZAccessControl_ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
        _grantRole(ADMIN_ROLE, _defaultAdmin);
    }
    /// @notice Grant admin role with event logging
    function grantAdminRole(address _account, string memory _reason) external onlyRole(ADMIN_ROLE) {
        _preGrant(ADMIN_ROLE, _account);
        _grantRole(ADMIN_ROLE, _account);
        emit RoleGrantedWithReason(ADMIN_ROLE, _account, msg.sender, _reason);
    }
    /// @notice Grant config manager role with event logging
    function grantConfigManagerRole(address _account, string memory _reason) external onlyRole(ADMIN_ROLE) {
        _preGrant(CONFIG_MANAGER_ROLE, _account);
        _grantRole(CONFIG_MANAGER_ROLE, _account);
        emit RoleGrantedWithReason(CONFIG_MANAGER_ROLE, _account, msg.sender, _reason);
    }
    /// @notice Grant harvester role with event logging
    function grantHarvesterRole(address _account, string memory _reason) external onlyRole(ADMIN_ROLE) {
        _preGrant(HARVESTER_ROLE, _account);
        _grantRole(HARVESTER_ROLE, _account);
        emit RoleGrantedWithReason(HARVESTER_ROLE, _account, msg.sender, _reason);
    }
    /// @notice Grant emergency role with event logging
    function grantEmergencyRole(address _account, string memory _reason) external onlyRole(ADMIN_ROLE) {
        _preGrant(EMERGENCY_ROLE, _account);
        _grantRole(EMERGENCY_ROLE, _account);
        emit RoleGrantedWithReason(EMERGENCY_ROLE, _account, msg.sender, _reason);
    }
    /// @notice Revoke role with event logging
    function revokeRoleWithReason(bytes32 _role, address _account, string memory _reason)
        external
        onlyRole(ADMIN_ROLE)
    {
        _preRevoke(_role, _account);
        _revokeRole(_role, _account);
        emit RoleRevokedWithReason(_role, _account, msg.sender, _reason);
    }
    /// @notice Override base revokeRole to add same check
    function revokeRole(bytes32 _role, address _account) public override onlyRole(ADMIN_ROLE) {
        _preRevoke(_role, _account);
        _revokeRole(_role, _account);
    }
    /// @notice Check if account has admin privileges
    /// @return True if address has ADMIN_ROLE or DEFAULT_ADMIN_ROLE
    function isAdmin(address _account) external view returns (bool) {
        return hasRole(ADMIN_ROLE, _account) || hasRole(DEFAULT_ADMIN_ROLE, _account);
    }
    /// @notice Check if account is config manager
    /// @return True if address has CONFIG_MANAGER_ROLE
    function isConfigManager(address _account) external view returns (bool) {
        return hasRole(CONFIG_MANAGER_ROLE, _account);
    }
    /// @notice Check if account is harvester
    /// @return True if address has HARVESTER_ROLE
    function isHarvester(address _account) external view returns (bool) {
        return hasRole(HARVESTER_ROLE, _account);
    }
    /// @notice Check if account is emergency contact
    /// @return True if address has EMERGENCY_ROLE
    function isEmergency(address _account) external view returns (bool) {
        return hasRole(EMERGENCY_ROLE, _account);
    }
}
