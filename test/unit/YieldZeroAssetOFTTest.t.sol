// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../YieldZeroBaseTest.t.sol";

contract YieldZeroAssetOFTTest is YieldZeroBaseTest {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_Constructor_HubChain_MintsMaxSupply() public {
        assertEq(assetOFT_arb.totalSupply(), assetOFT_arb.MAX_SUPPLY());
        assertEq(assetOFT_arb.balanceOf(address(this)), assetOFT_arb.MAX_SUPPLY());
    }

    function test_Constructor_SpokeChain_NoMint() public {
        // ETH and POL are configured as SPOKE in base test
        assertEq(assetOFT_eth.totalSupply(), 0);
        assertEq(assetOFT_eth.balanceOf(address(this)), 0);
        assertEq(assetOFT_pol.totalSupply(), 0);
        assertEq(assetOFT_pol.balanceOf(address(this)), 0);
    }
}
