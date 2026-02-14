// SPDX-License-Identifier: MIT

pragma solidity ^0.8.33;

import "forge-std/Test.sol";

import "../YieldZeroBaseTest.t.sol";

import "../../src/omnichain/YieldZeroMessager.sol";

import "../../src/errors/Errors.sol";

contract YieldZeroMessagerTest is YieldZeroBaseTest {
    YieldZeroMessager public yieldZeroMessager;

    address public owner = makeAddr("owner");

    address public hub = makeAddr("hub");

    function setUp() public virtual override {
        super.setUp();

        yieldZeroMessager = new YieldZeroMessager(address(endpoints[ARB_EID]), hub, owner);

        vm.label(address(yieldZeroMessager), "YieldZeroMessager");
    }

    // Initialization Tests

    function test_initialization() public {
        assertEq(yieldZeroMessager.yieldZeroHub(), hub);

        assertEq(yieldZeroMessager.owner(), owner);
    }

    // Hub Management Tests

    function test_setHub() public {
        address newHub = makeAddr("newHub");

        vm.prank(owner);

        yieldZeroMessager.setHub(newHub);

        assertEq(yieldZeroMessager.yieldZeroHub(), newHub);
    }

    function test_setHubNonOwner() public {
        address newHub = makeAddr("newHub");

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));

        yieldZeroMessager.setHub(newHub);
    }

    // Peer Management Tests

    function test_setPeer() public {
        bytes32 peerAddress = bytes32(uint256(0x1234));

        vm.prank(owner);

        yieldZeroMessager.setPeer(ETH_EID, peerAddress);

        assertEq(yieldZeroMessager.getPeer(ETH_EID), peerAddress);
    }

    function test_getPeer() public {
        bytes32 peerAddress = bytes32(uint256(0x1234));

        vm.prank(owner);

        yieldZeroMessager.setPeer(ETH_EID, peerAddress);

        assertEq(yieldZeroMessager.getPeer(ETH_EID), peerAddress);
    }

    // Message Sending Tests

    function test_sendStateSync() public {
        bytes32 peer1 = bytes32(uint256(0x1));

        bytes32 peer2 = bytes32(uint256(0x2));

        vm.prank(owner);

        yieldZeroMessager.setPeer(ETH_EID, peer1);

        vm.prank(owner);

        yieldZeroMessager.setPeer(POL_EID, peer2);

        // This will fail because we're not paying fees, but it should attempt to send

        vm.expectRevert(YZMessager_InvalidFeeValue.selector);

        vm.prank(owner);

        yieldZeroMessager.sendStateSync(100 ether, 100 ether, 10 ether);
    }

    function test_sendFeeUpdate() public {
        bytes32 peer = bytes32(uint256(0x1));

        vm.prank(owner);

        yieldZeroMessager.setPeer(ETH_EID, peer);

        vm.expectRevert(YZMessager_InvalidFeeValue.selector);

        vm.prank(owner);

        yieldZeroMessager.sendFeeUpdate(ETH_EID, 200);
    }

    function test_sendPauseUpdate() public {
        bytes32 peer = bytes32(uint256(0x1));

        vm.prank(owner);

        yieldZeroMessager.setPeer(ETH_EID, peer);

        vm.expectRevert(YZMessager_InvalidFeeValue.selector);

        vm.prank(owner);

        yieldZeroMessager.sendPauseUpdate(ETH_EID, true);
    }

    function test_sendHarvestDistribution() public {
        bytes32 peer = bytes32(uint256(0x1));

        vm.prank(owner);

        yieldZeroMessager.setPeer(ETH_EID, peer);

        vm.expectRevert(YZMessager_InvalidFeeValue.selector);

        vm.prank(owner);

        yieldZeroMessager.sendHarvestDistribution(ETH_EID, 10 ether);
    }

    function test_sendEmergencyStop() public {
        bytes32 peer = bytes32(uint256(0x1));

        vm.prank(owner);

        yieldZeroMessager.setPeer(ETH_EID, peer);

        vm.expectRevert(YZMessager_InvalidFeeValue.selector);

        vm.prank(owner);

        yieldZeroMessager.sendEmergencyStop();
    }

    // Fallback Tests

    function test_receiveEth() public {
        uint256 initialBalance = address(yieldZeroMessager).balance;

        (bool success,) = address(yieldZeroMessager).call{value: 1 ether}("");
        require(success, "Transfer failed");

        assertEq(address(yieldZeroMessager).balance, initialBalance + 1 ether);
    }
}
