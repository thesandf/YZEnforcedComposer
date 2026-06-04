// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {IYZErrors} from "./IYZErrors.sol";

/**
 * @title IYZEnforcedComposer
 * @notice Interface for YZEnforcedComposer, managing multi-chain risks, caps, pauses, and whitelisting.
 */
interface IYZEnforcedComposer {
    // ======== Configuration Functions ========

    function setTVLCap(uint256 _tvlCap) external;
    function setUserCap(address _user, uint256 _cap) external;
    function batchSetUserCaps(address[] calldata _users, uint256[] calldata _caps) external;
    function pauseDeposits() external;
    function unpauseDeposits() external;
    function pauseRedemptions() external;
    function unpauseRedemptions() external;
    function pauseAll() external;
    function unpauseAll() external;
    function setWhitelistEnabled(bool _enabled) external;
    function setWhitelist(address _user, bool _status) external;
    function batchSetWhitelist(address[] calldata _users, bool[] calldata _statuses) external;
    function setAdmin(address _newAdmin) external;

    // ======== View Functions ========

    function admin() external view returns (address);
    function tvlCap() external view returns (uint256);
    function userDepositCap(address user) external view returns (uint256);
    function userDeposits(address user) external view returns (uint256);
    function depositsPaused() external view returns (bool);
    function redemptionsPaused() external view returns (bool);
    function whitelistEnabled() external view returns (bool);
    function whitelist(address user) external view returns (bool);

    function getTotalValueLocked() external view returns (uint256);
    function getUserShares(address _user) external view returns (uint256);
    function getUserAssets(address _user) external view returns (uint256);
    function getUserDepositInfo(address _user) external view returns (uint256 deposit, uint256 cap, uint256 remaining);
    function canDeposit(address _user, uint256 _amount) external view returns (bool allowed, string memory reason);

    // ======== Emergency Functions ========

    function emergencyWithdraw(uint256 _amount, address _to) external;
    function emergencyWithdrawShares(uint256 _amount, address _to) external;
    function emergencyWithdrawNative(uint256 _amount, address payable _to) external;
}
