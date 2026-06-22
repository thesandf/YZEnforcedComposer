// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../unit/YZEnforcedComposerBase.t.sol";

contract TVLInvariant is YZEnforcedComposerBase {
    function setUp() public override {
        super.setUp();
        targetContract(address(yzEnforcedComposer_arb));
    }

    function invariant_TVLNeverExceedsAssets() public view {
        assertLe(
            yzEnforcedComposer_arb.getTotalValueLocked(),
            vault_arb.totalAssets(),
            "TVL exceeds Vault totalAssets"
        );
    }
}
