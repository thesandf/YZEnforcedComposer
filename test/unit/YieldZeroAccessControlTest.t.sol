// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import "../YieldZeroBaseTest.t.sol";
import "../../src/access/YieldZeroAccessControl.sol";
import "../../src/errors/Errors.sol";
import "forge-std/Test.sol";

contract YieldZeroAccessControlTest is YieldZeroBaseTest {
    YieldZeroAccessControl public testAccessControl;
    address public admin = makeAddr("admin");
    address public configManager = makeAddr("configManager");
    address public harvester = makeAddr("harvester");
    address public emergencyRole = makeAddr("emergencyRole");
    address public attacker = makeAddr("attacker");

    function setUp() public virtual override {
        super.setUp();
        testAccessControl = new YieldZeroAccessControl(admin);

        vm.label(address(testAccessControl), "YieldZeroAccessControl");
        vm.label(admin, "Admin");
        vm.label(configManager, "ConfigManager");
        vm.label(harvester, "Harvester");
        vm.label(emergencyRole, "EmergencyRole");
        vm.label(attacker, "Attacker");
    }

    function test_initialization() public {
        assertTrue(testAccessControl.hasRole(testAccessControl.ADMIN_ROLE(), admin));
        assertFalse(testAccessControl.hasRole(testAccessControl.CONFIG_MANAGER_ROLE(), admin));
        assertFalse(testAccessControl.hasRole(testAccessControl.HARVESTER_ROLE(), admin));
        assertFalse(testAccessControl.hasRole(testAccessControl.EMERGENCY_ROLE(), admin));
    }

    function test_admin_can_grant_roles() public {
        vm.prank(admin);
        testAccessControl.grantConfigManagerRole(configManager, "Config management");
        assertTrue(testAccessControl.hasRole(testAccessControl.CONFIG_MANAGER_ROLE(), configManager));

        vm.prank(admin);
        testAccessControl.grantHarvesterRole(harvester, "Harvest operations");
        assertTrue(testAccessControl.hasRole(testAccessControl.HARVESTER_ROLE(), harvester));

        vm.prank(admin);
        testAccessControl.grantEmergencyRole(emergencyRole, "Emergency operations");
        assertTrue(testAccessControl.hasRole(testAccessControl.EMERGENCY_ROLE(), emergencyRole));
    }

    function test_admin_can_grant_admin_role() public {
        address newAdmin = makeAddr("newAdmin");

        vm.prank(admin);
        testAccessControl.grantAdminRole(newAdmin, "Secondary admin");

        assertTrue(testAccessControl.hasRole(testAccessControl.ADMIN_ROLE(), newAdmin));
    }

    function test_non_admin_cannot_grant_roles() public {
        bytes32 adminRole = testAccessControl.ADMIN_ROLE();
        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")), attacker, adminRole
            )
        );
        testAccessControl.grantConfigManagerRole(configManager, "Unauthorized attempt");
    }

    function test_role_revocation() public {
        bytes32 configManagerRole = testAccessControl.CONFIG_MANAGER_ROLE();
        vm.prank(admin);
        testAccessControl.grantConfigManagerRole(configManager, "Config management");
        assertTrue(testAccessControl.hasRole(configManagerRole, configManager));

        vm.prank(admin);
        testAccessControl.revokeRoleWithReason(configManagerRole, configManager, "Revoked access");

        assertFalse(testAccessControl.hasRole(configManagerRole, configManager));
    }

    function test_multiple_roles_per_account() public {
        address multiRole = makeAddr("multiRole");
        bytes32 configManagerRole = testAccessControl.CONFIG_MANAGER_ROLE();
        bytes32 harvesterRole = testAccessControl.HARVESTER_ROLE();

        vm.prank(admin);
        testAccessControl.grantConfigManagerRole(multiRole, "Config manager");

        vm.prank(admin);
        testAccessControl.grantHarvesterRole(multiRole, "Harvester");

        assertTrue(testAccessControl.hasRole(configManagerRole, multiRole));
        assertTrue(testAccessControl.hasRole(harvesterRole, multiRole));
    }

    function test_isAdmin_helper() public {
        assertTrue(testAccessControl.isAdmin(admin));
        assertFalse(testAccessControl.isAdmin(attacker));
    }

    function test_isConfigManager_helper() public {
        vm.prank(admin);
        testAccessControl.grantConfigManagerRole(configManager, "Config management");

        assertTrue(testAccessControl.isConfigManager(configManager));
        assertFalse(testAccessControl.isConfigManager(attacker));
    }

    function test_isHarvester_helper() public {
        vm.prank(admin);
        testAccessControl.grantHarvesterRole(harvester, "Harvest operations");

        assertTrue(testAccessControl.isHarvester(harvester));
        assertFalse(testAccessControl.isHarvester(attacker));
    }

    function test_isEmergency_helper() public {
        vm.prank(admin);
        testAccessControl.grantEmergencyRole(emergencyRole, "Emergency operations");

        assertTrue(testAccessControl.isEmergency(emergencyRole));
        assertFalse(testAccessControl.isEmergency(attacker));
    }

    function test_revoke_with_reason() public {
        bytes32 configManagerRole = testAccessControl.CONFIG_MANAGER_ROLE();
        vm.prank(admin);
        testAccessControl.grantConfigManagerRole(configManager, "Config management");

        vm.prank(admin);
        testAccessControl.revokeRoleWithReason(configManagerRole, configManager, "Test reason");
    }

    function test_grant_with_reason() public {
        vm.prank(admin);
        testAccessControl.grantConfigManagerRole(configManager, "Test reason");

        assertTrue(testAccessControl.hasRole(testAccessControl.CONFIG_MANAGER_ROLE(), configManager));
    }

    function test_admin_cannot_revoke_own_admin_role() public {
        // Let's see what roles the admin has (static calls, no prank needed)
        bool hasAdminRole = testAccessControl.hasRole(testAccessControl.ADMIN_ROLE(), admin);
        bool hasDefaultAdminRole = testAccessControl.hasRole(testAccessControl.DEFAULT_ADMIN_ROLE(), admin);

        console.log("Admin has ADMIN_ROLE:", hasAdminRole);
        console.log("Admin has DEFAULT_ADMIN_ROLE:", hasDefaultAdminRole);

        bytes32 adminRole = testAccessControl.ADMIN_ROLE();

        console.log("Calling revokeRoleWithReason with role:", uint256(adminRole));
        console.log("Calling revokeRoleWithReason with account:", admin);

        vm.prank(admin);
        vm.expectRevert(YZAccessControl_CallerNotAdmin.selector);
        testAccessControl.revokeRoleWithReason(adminRole, admin, "Cannot revoke own role");
    }

    function test_renounce_role() public {
        address renouncer = makeAddr("renouncer");
        bytes32 configManagerRole = testAccessControl.CONFIG_MANAGER_ROLE();

        vm.prank(admin);
        testAccessControl.grantConfigManagerRole(renouncer, "Config management");

        vm.prank(renouncer);
        testAccessControl.renounceRole(configManagerRole, renouncer);

        assertFalse(testAccessControl.hasRole(configManagerRole, renouncer));
    }

    function test_cannot_renounce_role_not_held() public {
        bytes32 configManagerRole = testAccessControl.CONFIG_MANAGER_ROLE();
        vm.prank(attacker);
        testAccessControl.renounceRole(configManagerRole, attacker);
        assertFalse(testAccessControl.hasRole(configManagerRole, attacker));
    }
}
