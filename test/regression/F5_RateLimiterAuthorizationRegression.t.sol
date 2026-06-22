// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {RateLimiter} from "../../src/protocol/security/RateLimiter.sol";

contract F5_RateLimiterAuthorizationRegression is Test {
    RateLimiter public rateLimiter;
    address public owner = address(this);
    address public victim = makeAddr("victim");
    address public attacker = makeAddr("attacker");

    function setUp() public {
        // Setup rate limiter with a limit of 5 operations per window
        rateLimiter = new RateLimiter(5, owner);
    }

    /**
     * @notice Verifies that an unauthorized caller is blocked from calling recordOperation with custom error
     */
    function test_Regression_UnauthorizedCallerReverts() public {
        vm.prank(attacker);
        vm.expectRevert(RateLimiter.UnauthorizedCaller.selector);
        rateLimiter.recordOperation(victim);
    }

    /**
     * @notice Verifies that an authorized caller can successfully call recordOperation
     */
    function test_Regression_AuthorizedCallerSucceeds() public {
        // Authorize this test contract
        vm.prank(owner);
        rateLimiter.setAuthorizedCaller(address(this), true);

        // Record operation
        rateLimiter.recordOperation(victim);

        // Verify operation count
        uint256 currentWindow = block.timestamp / rateLimiter.RATE_LIMIT_WINDOW();
        uint256 count = rateLimiter.operationCount(victim, currentWindow);
        assertEq(count, 1, "Operation was not recorded successfully!");
    }
}
