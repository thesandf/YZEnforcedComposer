// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {YZEnforcedComposer} from "../../src/YZEnforcedComposer.sol";
import "./YZEnforcedComposerBase.t.sol";

contract YZEnforcedComposerConstructorTest is YZEnforcedComposerBase {
    function test_Constructor_SetsAdmin() public view {
        assertEq(yzEnforcedComposer_arb.admin(), admin);
    }

    function test_Constructor_SetsVersion() public view {
        assertEq(yzEnforcedComposer_arb.PARENT_VERSION_PINNED(), "ovault-evm@1.0.0");
    }

    function test_Constructor_RevertsOnZeroAdmin() public {
        vm.expectRevert(YZEnforcedComposer.YZ_ZeroAddress.selector);
        new YZEnforcedComposer(address(vault_arb), address(assetOFT_arb), address(shareOFT_arb), address(0));
    }

    function test_Constructor_InitialPauseStates() public view {
        assertFalse(yzEnforcedComposer_arb.depositsPaused());
        assertFalse(yzEnforcedComposer_arb.redemptionsPaused());
        assertFalse(yzEnforcedComposer_arb.whitelistEnabled());
        assertEq(yzEnforcedComposer_arb.tvlCap(), 0);
    }
}
