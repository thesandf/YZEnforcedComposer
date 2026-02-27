// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../access/YieldZeroAccessControl.sol";

contract TestHelper {
    event LogResult(string what, bool success, string reason);
    event LogState(address admin, address msgSender, bytes32 adminRole, bool hasAdminRole, bool hasDefaultAdminRole);

    YieldZeroAccessControl public accessControl;

    constructor() {
        accessControl = new YieldZeroAccessControl(msg.sender);
    }

    function test1() external {
        emit LogState(
            msg.sender,
            msg.sender,
            accessControl.ADMIN_ROLE(),
            accessControl.hasRole(accessControl.ADMIN_ROLE(), msg.sender),
            accessControl.hasRole(accessControl.DEFAULT_ADMIN_ROLE(), msg.sender)
        );

        bool success;
        string memory reason;

        try accessControl.revokeRoleWithReason(accessControl.ADMIN_ROLE(), msg.sender, "test1") {
            reason = "Success";
            success = true;
        } catch Error(string memory err) {
            reason = err;
            success = false;
        } catch {
            reason = "Unknown error";
            success = false;
        }

        emit LogResult("test1", success, reason);
    }

    function test2() external {
        emit LogState(
            msg.sender,
            msg.sender,
            accessControl.ADMIN_ROLE(),
            accessControl.hasRole(accessControl.ADMIN_ROLE(), msg.sender),
            accessControl.hasRole(accessControl.DEFAULT_ADMIN_ROLE(), msg.sender)
        );

        bool success;
        string memory reason;

        try accessControl.revokeRole(accessControl.ADMIN_ROLE(), msg.sender) {
            reason = "Success";
            success = true;
        } catch Error(string memory err) {
            reason = err;
            success = false;
        } catch {
            reason = "Unknown error";
            success = false;
        }

        emit LogResult("test2", success, reason);
    }
}
