// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title IYZErrors
 * @notice Consolidated custom error definitions for the YZEnforcedComposer contract
 */
abstract contract IYZErrors {
    error YZ_DepositsPaused();
    error YZ_RedemptionsPaused();
    error YZ_TVLCapExceeded(uint256 currentTVL, uint256 attemptedDeposit, uint256 tvlCap);
    error YZ_UserCapExceeded(address user, uint256 currentDeposit, uint256 attemptedDeposit, uint256 userCap);
    error YZ_NotWhitelisted(address user);
    error YZ_NotAdmin();
    error YZ_ZeroAddress();
}
