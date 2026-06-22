// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../unit/YZEnforcedComposerBase.t.sol";
import {YieldZeroComposer} from "../../src/protocol/omnichain/YieldZeroComposer.sol";

contract F3_TVLUnitMismatchRegression is YZEnforcedComposerBase {
    YieldZeroComposer public yzComposer;

    function setUp() public override {
        super.setUp();
        // Instantiating YieldZeroComposer helper contract
        yzComposer = new YieldZeroComposer(
            address(vault_arb),
            address(assetOFT_arb),
            address(shareOFT_arb),
            address(this),
            address(accessControl)
        );
        vm.prank(address(this));
        vault_arb.setComposer(address(yzComposer));
    }

    /**
     * @notice Verifies that TVL invariant check passes after deposits, yield accruals, and redemptions
     */
    function test_Regression_TVLInvariantMaintained() public {
        uint256 amount = 10 ether;

        _fundLocalFromHub(address(this), amount);
        assetOFT_arb.approve(address(yzComposer), amount);

        SendParam memory dep = _buildHopParam(address(0), address(this), ARB_EID, amount);
        yzComposer.initiateDepositAndSend(amount, 0, dep, address(this));

        // Yield accrues inside the vault (simulate by dealing assets to vault)
        deal(address(assetOFT_arb), address(vault_arb), 20 ether);

        uint256 shares = 5 ether;
        vault_arb.approve(address(yzComposer), shares);

        SendParam memory red = _buildHopParam(address(0), address(this), ARB_EID, shares);
        yzComposer.initiateRedeemAndSend(shares, 0, red, address(this));

        assertTrue(yzComposer.invariantCheck(), "Accounting invariant was broken!");
    }

    /**
     * @notice Verifies that TVL invariant check passes even after massive yield accrual and partial redemption
     */
    function test_RedeemAfterLargeYieldMaintainsInvariant() public {
        uint256 amount = 100 ether;

        _fundLocalFromHub(address(this), amount);
        assetOFT_arb.approve(address(yzComposer), amount);

        SendParam memory dep = _buildHopParam(address(0), address(this), ARB_EID, amount);
        yzComposer.initiateDepositAndSend(amount, 0, dep, address(this));

        // Yield accrues massively inside the vault (simulate by dealing assets to vault)
        deal(address(assetOFT_arb), address(vault_arb), 1000 ether);

        uint256 shares = 10 ether;
        vault_arb.approve(address(yzComposer), shares);

        SendParam memory red = _buildHopParam(address(0), address(this), ARB_EID, shares);
        yzComposer.initiateRedeemAndSend(shares, 0, red, address(this));

        assertTrue(yzComposer.invariantCheck(), "Accounting invariant was broken after large yield!");
    }

    /**
     * @notice Verifies that TVL invariant holds even after multiple compounding yield epochs and partial redemptions
     */
    function test_TVLInvariantAfterMultipleYieldEpochs() public {
        uint256 amount = 100 ether;

        _fundLocalFromHub(address(this), amount);
        assetOFT_arb.approve(address(yzComposer), amount);

        SendParam memory dep = _buildHopParam(address(0), address(this), ARB_EID, amount);
        yzComposer.initiateDepositAndSend(amount, 0, dep, address(this));

        // Yield epoch 1 (simulate yield growth)
        deal(address(assetOFT_arb), address(vault_arb), 200 ether);

        // Partial redeem 1
        uint256 shares1 = 10 ether;
        vault_arb.approve(address(yzComposer), shares1);
        SendParam memory red1 = _buildHopParam(address(0), address(this), ARB_EID, shares1);
        yzComposer.initiateRedeemAndSend(shares1, 0, red1, address(this));

        assertTrue(yzComposer.invariantCheck(), "Invariant broken after yield epoch 1");

        // Yield epoch 2
        deal(address(assetOFT_arb), address(vault_arb), 500 ether);

        // Partial redeem 2
        uint256 shares2 = 20 ether;
        vault_arb.approve(address(yzComposer), shares2);
        SendParam memory red2 = _buildHopParam(address(0), address(this), ARB_EID, shares2);
        yzComposer.initiateRedeemAndSend(shares2, 0, red2, address(this));

        assertTrue(yzComposer.invariantCheck(), "Invariant broken after yield epoch 2");

        // Yield epoch 3
        deal(address(assetOFT_arb), address(vault_arb), 1000 ether);

        // Final redeem
        uint256 shares3 = 5 ether;
        vault_arb.approve(address(yzComposer), shares3);
        SendParam memory red3 = _buildHopParam(address(0), address(this), ARB_EID, shares3);
        yzComposer.initiateRedeemAndSend(shares3, 0, red3, address(this));

        assertTrue(yzComposer.invariantCheck(), "Invariant broken after yield epoch 3");
    }
}
