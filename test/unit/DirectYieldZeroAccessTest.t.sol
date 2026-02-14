// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import "../../src/access/YieldZeroAccessControl.sol";
import "../../src/errors/Errors.sol";
import "forge-std/Test.sol";

contract DirectYieldZeroAccessTest is Test {
    YieldZeroAccessControl public accessControl;
    address public admin = makeAddr("admin");

    function setUp() public {
        vm.prank(admin);
        accessControl = new YieldZeroAccessControl(admin);
        vm.label(address(accessControl), "YieldZeroAccessControl");
        vm.label(admin, "Admin");
    }

    function testDirectRevoke() public {
        /// Check admin roles
        bool hasAdminRoleBefore = accessControl.hasRole(accessControl.ADMIN_ROLE(), admin);
        bool hasDefaultAdminRoleBefore = accessControl.hasRole(accessControl.DEFAULT_ADMIN_ROLE(), admin);

        assertTrue(hasAdminRoleBefore);
        assertTrue(hasDefaultAdminRoleBefore);

        bytes32 adminRole = accessControl.ADMIN_ROLE();

        /// Now prank for the actual revoke call
        vm.prank(admin);
        vm.expectRevert(YZAccessControl_CallerNotAdmin.selector);
        accessControl.revokeRoleWithReason(adminRole, admin, "Test revocation");

        /// Check roles again
        bool hasAdminRoleAfter = accessControl.hasRole(adminRole, admin);
        bool hasDefaultAdminRoleAfter = accessControl.hasRole(accessControl.DEFAULT_ADMIN_ROLE(), admin);

        assertTrue(hasAdminRoleAfter);
        assertTrue(hasDefaultAdminRoleAfter);
    }
}
