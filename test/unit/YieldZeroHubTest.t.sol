// SPDX-License-Identifier: MIT

pragma solidity ^0.8.33;

import "forge-std/Test.sol";

import "../YieldZeroBaseTest.t.sol";

import "../../src/omnichain/YieldZeroHub.sol";

import "../../src/omnichain/YieldZeroMessager.sol";

import "../../src/errors/Errors.sol";

contract YieldZeroHubTest is YieldZeroBaseTest {
    YieldZeroHub public yieldZeroHub;

    YieldZeroMessager public yieldZeroMessager;

    address public owner = makeAddr("owner");

    address public feeRecipient = makeAddr("feeRecipient");

    function setUp() public virtual override {
        super.setUp();

        // Deploy YieldZeroHub first

        yieldZeroHub = new YieldZeroHub(address(vault_arb), address(yieldZeroComposer_arb), feeRecipient, owner);

        // Deploy YieldZeroMessager with valid hub address

        yieldZeroMessager = new YieldZeroMessager(address(endpoints[ARB_EID]), address(yieldZeroHub), owner);

        // Set messager in hub

        vm.prank(owner);

        yieldZeroHub.setMessager(payable(address(yieldZeroMessager)));

        vm.label(address(yieldZeroHub), "YieldZeroHub");

        vm.label(address(yieldZeroMessager), "YieldZeroMessager");
    }

    // Hub Initialization Tests

    function test_initialization() public {
        assertEq(yieldZeroHub.vault(), address(vault_arb));

        assertEq(yieldZeroHub.composer(), address(yieldZeroComposer_arb));

        assertEq(yieldZeroHub.feeRecipient(), feeRecipient);

        assertEq(yieldZeroHub.feeBasisPoints(), 100); // 1%

        assertFalse(yieldZeroHub.isPaused());

        assertTrue(yieldZeroHub.harvestEnabled());

        assertEq(yieldZeroHub.messager(), address(yieldZeroMessager));
    }

    // Spoke Management Tests

    function test_connectSpoke() public {
        vm.prank(owner);

        yieldZeroHub.connectSpoke(ETH_EID, makeAddr("ethSpoke"));

        assertTrue(yieldZeroHub.isSpokeConnected(ETH_EID));
    }

    function test_disconnectSpoke() public {
        vm.prank(owner);

        yieldZeroHub.connectSpoke(ETH_EID, makeAddr("ethSpoke"));

        vm.prank(owner);

        yieldZeroHub.disconnectSpoke(ETH_EID);

        assertFalse(yieldZeroHub.isSpokeConnected(ETH_EID));
    }

    function test_getConnectedSpokeEids() public {
        vm.prank(owner);

        yieldZeroHub.connectSpoke(ETH_EID, makeAddr("ethSpoke"));

        vm.prank(owner);

        yieldZeroHub.connectSpoke(POL_EID, makeAddr("polSpoke"));

        uint32[] memory eids = yieldZeroHub.getConnectedSpokeEids();

        assertEq(eids.length, 2);

        bool hasEthEid = false;

        bool hasPolEid = false;

        for (uint256 i = 0; i < eids.length; i++) {
            if (eids[i] == ETH_EID) hasEthEid = true;

            if (eids[i] == POL_EID) hasPolEid = true;
        }

        assertTrue(hasEthEid);

        assertTrue(hasPolEid);
    }

    // Fee Management Tests

    function test_setFeeBasisPoints() public {
        vm.prank(owner);
        yieldZeroHub.setFeeBasisPoints(200); // 2%

        assertEq(yieldZeroHub.feeBasisPoints(), 200);
    }

    function test_setFeeRecipient() public {
        address newRecipient = makeAddr("newRecipient");

        vm.prank(owner);

        yieldZeroHub.setFeeRecipient(newRecipient);

        assertEq(yieldZeroHub.feeRecipient(), newRecipient);
    }

    // Harvest Tests

    function test_triggerHarvest() public {
        vm.prank(owner);
        yieldZeroHub.connectSpoke(ETH_EID, makeAddr("ethSpoke"));

        vm.prank(owner);
        yieldZeroHub.connectSpoke(POL_EID, makeAddr("polSpoke"));

        // Set peer addresses for the connected spokes on the messager
        vm.prank(owner);
        yieldZeroMessager.setPeer(ETH_EID, bytes32(uint256(uint160(makeAddr("ethSpoke")))));

        vm.prank(owner);
        yieldZeroMessager.setPeer(POL_EID, bytes32(uint256(uint160(makeAddr("polSpoke")))));

        // Send eth to the hub to pay for fees
        vm.deal(address(yieldZeroHub), 10 ether);

        // Send eth to the messager to pay for fees
        vm.deal(address(yieldZeroMessager), 100 ether);

        // Debug: Print balances before harvest
        console.log("Hub balance before harvest:", address(yieldZeroHub).balance);
        console.log("Messager balance before harvest:", address(yieldZeroMessager).balance);

        // Set last harvest time to allow harvest
        vm.warp(block.timestamp + yieldZeroHub.HARVEST_INTERVAL());

        vm.prank(owner);
        yieldZeroHub.triggerHarvest(100 ether);

        // Verify fees collected
        uint256 fee = 100 ether * 100 / 10000; // 1% fee
        assertEq(yieldZeroHub.totalFeesCollected(), fee);
    }

    function test_triggerHarvestTooSoon() public {
        vm.prank(owner);
        yieldZeroHub.connectSpoke(ETH_EID, makeAddr("ethSpoke"));

        vm.prank(owner);
        yieldZeroMessager.setPeer(ETH_EID, bytes32(uint256(uint160(makeAddr("ethSpoke")))));

        // Send eth to the hub to pay for fees
        vm.deal(address(yieldZeroHub), 10 ether);

        // Send eth to the messager to pay for fees
        vm.deal(address(yieldZeroMessager), 100 ether);

        vm.warp(block.timestamp + yieldZeroHub.HARVEST_INTERVAL());

        vm.prank(owner);
        yieldZeroHub.triggerHarvest(100 ether);

        vm.expectRevert(YZHub_HarvestNotReady.selector);

        vm.prank(owner);
        yieldZeroHub.triggerHarvest(100 ether);
    }

    function test_triggerHarvestWhenPaused() public {
        vm.prank(owner);

        yieldZeroHub.setPaused(true);

        vm.expectRevert(YZHub_Paused.selector);

        vm.prank(owner);

        yieldZeroHub.triggerHarvest(100 ether);
    }

    // State Sync Tests

    function test_syncStateToSpokes() public {
        vm.prank(owner);

        yieldZeroHub.connectSpoke(ETH_EID, makeAddr("ethSpoke"));

        vm.prank(owner);

        yieldZeroHub.syncStateToSpokes();
    }

    // Emergency Stop Tests

    function test_triggerEmergencyStop() public {
        vm.prank(owner);

        yieldZeroHub.connectSpoke(ETH_EID, makeAddr("ethSpoke"));

        vm.prank(owner);

        yieldZeroHub.triggerEmergencyStop();

        assertTrue(yieldZeroHub.isPaused());
    }

    // Hub Status Tests

    function test_getHubStatus() public {
        (address vaultAddr, address composerAddr, bool paused, uint256 fee, uint256 tvl) = yieldZeroHub.getHubStatus();

        assertEq(vaultAddr, address(vault_arb));

        assertEq(composerAddr, address(yieldZeroComposer_arb));

        assertFalse(paused);

        assertEq(fee, 100);

        assertEq(tvl, 0);
    }

    function test_getVaultStats() public {
        (uint256 totalAssets, uint256 totalSupply, uint256 totalYield, uint256 tvl) = yieldZeroHub.getVaultStats();

        assertEq(totalAssets, 0);

        assertEq(totalSupply, 0);

        assertEq(totalYield, 0);

        assertEq(tvl, 0);
    }
}
