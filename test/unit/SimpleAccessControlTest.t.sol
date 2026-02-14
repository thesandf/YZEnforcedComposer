// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import "../../src/access/YieldZeroAccessControl.sol";
import "../../src/errors/Errors.sol";
import "forge-std/Test.sol";

contract SimpleAccessControlTest is Test {
    YieldZeroAccessControl public testAccessControl;
    address public admin = makeAddr("admin");

    function setUp() public {
        testAccessControl = new YieldZeroAccessControl(admin);
        vm.label(address(testAccessControl), "YieldZeroAccessControl");
        vm.label(admin, "Admin");
    }

    function testSimpleRevoke() public {
        // Test that we can revoke a role from someone else
        address otherAccount = makeAddr("otherAccount");

        vm.startPrank(admin);
        testAccessControl.grantAdminRole(otherAccount, "Test admin");
        assertTrue(testAccessControl.hasRole(testAccessControl.ADMIN_ROLE(), otherAccount));

        testAccessControl.revokeRoleWithReason(testAccessControl.ADMIN_ROLE(), otherAccount, "Test revocation");
        assertFalse(testAccessControl.hasRole(testAccessControl.ADMIN_ROLE(), otherAccount));
        vm.stopPrank();
    }

    function testAdminCannotRevokeOwnRole() public {
        assertTrue(testAccessControl.hasRole(testAccessControl.ADMIN_ROLE(), admin));

        bytes32 adminRole = testAccessControl.ADMIN_ROLE();

        vm.prank(admin);
        vm.expectRevert(YZAccessControl_CallerNotAdmin.selector);
        testAccessControl.revokeRoleWithReason(adminRole, admin, "Cannot revoke own role");
    }
}
