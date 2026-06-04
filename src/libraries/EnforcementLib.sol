// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IYZErrors} from "../interfaces/IYZErrors.sol";

/**
 * @title EnforcementLib
 * @notice Stateless library that enforces TVL caps, user caps, and whitelisting for YieldZero risk levels.
 */
library EnforcementLib {
    /**
     * @notice Enforce whitelist status of a depositor
     * @param _depositor Address of the depositor
     * @param _whitelistEnabled Whether whitelist checks are active
     * @param _isWhitelisted Whether the depositor is whitelisted
     */
    function enforceWhitelist(address _depositor, bool _whitelistEnabled, bool _isWhitelisted) internal pure {
        if (_whitelistEnabled && !_isWhitelisted) {
            revert IYZErrors.YZ_NotWhitelisted(_depositor);
        }
    }

    /**
     * @notice Enforce TVL Cap limits
     * @param _currentTVL Current TVL inside the vault
     * @param _attemptedDeposit Amount being deposited in this transaction
     * @param _tvlCap Maximum TVL allowed (0 means disabled)
     */
    function enforceTVLCap(uint256 _currentTVL, uint256 _attemptedDeposit, uint256 _tvlCap) internal pure {
        if (_tvlCap > 0 && _currentTVL + _attemptedDeposit > _tvlCap) {
            revert IYZErrors.YZ_TVLCapExceeded(_currentTVL, _attemptedDeposit, _tvlCap);
        }
    }

    /**
     * @notice Enforce user per-address deposit caps
     * @param _depositor Address of the depositor
     * @param _currentDeposit Amount already deposited by the user
     * @param _attemptedDeposit Amount being deposited in this transaction
     * @param _userCap Cap limit for this user (0 means disabled)
     */
    function enforceUserCap(address _depositor, uint256 _currentDeposit, uint256 _attemptedDeposit, uint256 _userCap)
        internal
        pure
    {
        if (_userCap > 0 && _currentDeposit + _attemptedDeposit > _userCap) {
            revert IYZErrors.YZ_UserCapExceeded(_depositor, _currentDeposit, _attemptedDeposit, _userCap);
        }
    }
}
