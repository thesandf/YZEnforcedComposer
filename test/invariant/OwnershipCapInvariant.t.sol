// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../unit/YZEnforcedComposerBase.t.sol";

contract OwnershipCapInvariant is YZEnforcedComposerBase {
    function setUp() public override {
        super.setUp();
        targetContract(address(yzEnforcedComposer_arb));
    }

    function invariant_OwnershipNeverExceedsCap() public view {
        address[] memory users = _getAllTestUsers();
        for (uint256 i = 0; i < users.length; i++) {
            (uint256 ownership, uint256 cap, ) = yzEnforcedComposer_arb.getUserCapUsage(users[i]);
            if (cap > 0) {
                assertLe(ownership, cap, "User ownership exceeds cap");
            }
        }
    }

    function _getAllTestUsers() internal view returns (address[] memory) {
        address[] memory users = new address[](3);
        users[0] = userA;
        users[1] = userB;
        users[2] = nonAdmin;
        return users;
    }
}
