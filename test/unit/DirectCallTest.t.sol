// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import "../../src/access/YieldZeroAccessControl.sol";
import "forge-std/Test.sol";

contract TestCaller {
    YieldZeroAccessControl public accessControl;
    address public admin;

    event CallResult(bool success, string reason);
    event ContractInfo(address adminAddr, address actualMsgSender, bytes32 adminRoleHash);

    constructor(address _admin) {
        accessControl = new YieldZeroAccessControl(_admin);
        admin = _admin;
        emit ContractInfo(_admin, address(0), accessControl.ADMIN_ROLE());
    }

    function callRevoke() public returns (bool) {
        bool success = true;
        string memory reason = "success";

        emit ContractInfo(admin, msg.sender, accessControl.ADMIN_ROLE());

        try accessControl.revokeRoleWithReason(accessControl.ADMIN_ROLE(), admin, "Test") {
            reason = "call succeeded - no revert!";
        } catch Error(string memory err) {
            reason = err;
            success = false;
        } catch {
            reason = "unknown error";
            success = false;
        }

        emit CallResult(success, reason);
        return success;
    }

    function callRevokeDirect() public returns (bool) {
        bool success = true;
        string memory reason = "success";

        emit ContractInfo(admin, msg.sender, accessControl.ADMIN_ROLE());

        try accessControl.revokeRoleWithReason(accessControl.ADMIN_ROLE(), msg.sender, "Test") {
            reason = "call succeeded - no revert!";
        } catch Error(string memory err) {
            reason = err;
            success = false;
        } catch {
            reason = "unknown error";
            success = false;
        }

        emit CallResult(success, reason);
        return success;
    }
}

contract DirectCallTest is Test {
    TestCaller public testCaller;
    address public admin = makeAddr("admin");

    function setUp() public {
        testCaller = new TestCaller(admin);
        vm.label(address(testCaller), "TestCaller");
        vm.label(admin, "Admin");
    }

    function testDirectCall() public {
        vm.prank(admin);
        bool result = testCaller.callRevoke();

        assertFalse(result, "Expected call to fail");
    }

    function testDirectCall2() public {
        vm.prank(admin);
        bool result = testCaller.callRevokeDirect();

        assertFalse(result, "Expected call to fail");
    }
}
