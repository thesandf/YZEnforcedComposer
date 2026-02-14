// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import "forge-std/Test.sol";

contract HashTest is Test {
    function testKeccak256() public {
        string memory role = "ADMIN_ROLE";
        bytes32 roleHash = keccak256(bytes(role));
        bytes32 constantHash = 0xa49807205ce4d355092ef5a8a18f56e8913cf4a201fbe287825b095693c21775;

        assertTrue(roleHash == constantHash, "keccak256('ADMIN_ROLE') should match ADMIN_ROLE constant");
    }
}
