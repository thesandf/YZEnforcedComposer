// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {YZEnforcedComposer} from "../../src/YZEnforcedComposer.sol";
import {YieldZeroVault} from "../../src/protocol/core/YieldZeroVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../unit/YZEnforcedComposerBase.t.sol";

contract YZEnforcedComposerReentrancyTest is YZEnforcedComposerBase {
    // Malicious contract that attempts reentrancy attacks
    MaliciousVault public maliciousVault;

    function setUp() public override {
        super.setUp();

        // Deploy malicious vault to extract its bytecode
        MaliciousVault maliciousImplementation = new MaliciousVault(
            "YieldZero Share",
            "YZS",
            IERC20(address(assetOFT_arb)),
            address(yzEnforcedComposer_arb),
            address(accessControl)
        );

        // Etch the malicious bytecode onto the real vault_arb address
        vm.etch(address(vault_arb), address(maliciousImplementation).code);

        // Cast vault_arb to MaliciousVault to call configurations
        maliciousVault = MaliciousVault(address(vault_arb));
    }

    function test_Reentrancy_DepositAndSend_NotVulnerable() public {
        _fundLocalFromHub(userA, 100 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 100 ether);

        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 100 ether);

        // Malicious user tries to reenter during deposit
        maliciousVault.setReentrancyTarget(address(yzEnforcedComposer_arb), 1);

        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSignature("ReentrancyGuardReentrantCall()"));
        yzEnforcedComposer_arb.depositAndSend(100 ether, sendParam, userA);

        // Verify no state corruption
        assertEq(vault_arb.totalAssets(), 0);
        assertEq(yzEnforcedComposer_arb.getUserAssets(userA), 0);
    }

    function test_Reentrancy_RedeemAndSend_NotVulnerable() public {
        // First deposit normally
        _fundLocalFromHub(userA, 100 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 100 ether);

        SendParam memory depositParam = _buildHopParam(address(0), userA, ARB_EID, 100 ether);

        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(100 ether, depositParam, userA);

        // Now try to reenter during redeem
        vm.prank(userA);
        vault_arb.approve(address(yzEnforcedComposer_arb), 50 ether);

        SendParam memory redeemParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);

        maliciousVault.setReentrancyTarget(address(yzEnforcedComposer_arb), 2);

        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSignature("ReentrancyGuardReentrantCall()"));
        yzEnforcedComposer_arb.redeemAndSend(50 ether, redeemParam, userA);

        // Verify no state corruption
        assertEq(vault_arb.totalAssets(), 100 ether);
        assertEq(yzEnforcedComposer_arb.getUserAssets(userA), 100 ether);
    }

    function test_Reentrancy_EnforcementChecks_NotVulnerable() public {
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(100 ether);
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(userA, 100 ether);

        // User deposits to reach 50 ether
        _fundLocalFromHub(userA, 50 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 50 ether);

        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);

        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(50 ether, sendParam, userA);

        // Try to reenter during enforcement check
        _fundLocalFromHub(userA, 10 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(yzEnforcedComposer_arb), 10 ether);

        sendParam = _buildHopParam(address(0), userA, ARB_EID, 10 ether);

        maliciousVault.setReentrancyTarget(address(yzEnforcedComposer_arb), 3);

        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSignature("ReentrancyGuardReentrantCall()"));
        yzEnforcedComposer_arb.depositAndSend(10 ether, sendParam, userA);

        // Verify caps still enforced
        assertEq(vault_arb.totalAssets(), 50 ether);
        assertEq(yzEnforcedComposer_arb.getUserAssets(userA), 50 ether);
    }

    function test_Reentrancy_PauseControls_NotVulnerable() public {
        // Try to reenter during pause/unpause
        maliciousVault.setReentrancyTarget(address(yzEnforcedComposer_arb), 4);

        vm.prank(userA);
        vm.expectRevert(YZEnforcedComposer.YZ_NotAdmin.selector);
        yzEnforcedComposer_arb.pauseDeposits();

        vm.prank(userA);
        vm.expectRevert(YZEnforcedComposer.YZ_NotAdmin.selector);
        yzEnforcedComposer_arb.unpauseDeposits();
    }

    function test_Reentrancy_CapUpdates_NotVulnerable() public {
        // Try to reenter during cap updates
        maliciousVault.setReentrancyTarget(address(yzEnforcedComposer_arb), 5);

        vm.prank(userA);
        vm.expectRevert(YZEnforcedComposer.YZ_NotAdmin.selector);
        yzEnforcedComposer_arb.setTVLCap(200 ether);

        vm.prank(userA);
        vm.expectRevert(YZEnforcedComposer.YZ_NotAdmin.selector);
        yzEnforcedComposer_arb.setUserCap(userA, 100 ether);
    }

    function test_Reentrancy_WhitelistUpdates_NotVulnerable() public {
        // Try to reenter during whitelist updates
        maliciousVault.setReentrancyTarget(address(yzEnforcedComposer_arb), 6);

        vm.prank(userA);
        vm.expectRevert(YZEnforcedComposer.YZ_NotAdmin.selector);
        yzEnforcedComposer_arb.setWhitelistEnabled(true);

        vm.prank(userA);
        vm.expectRevert(YZEnforcedComposer.YZ_NotAdmin.selector);
        yzEnforcedComposer_arb.setWhitelist(userA, true);
    }

    function test_Reentrancy_EmergencyWithdraw_NotVulnerable() public {
        _fundLocalFromHub(address(yzEnforcedComposer_arb), 100 ether);

        // Try to reenter during emergency withdraw
        maliciousVault.setReentrancyTarget(address(yzEnforcedComposer_arb), 7);

        vm.prank(userA);
        vm.expectRevert(YZEnforcedComposer.YZ_NotAdmin.selector);
        yzEnforcedComposer_arb.emergencyWithdraw(50 ether, recipient);
    }
}

contract MaliciousVault is YieldZeroVault {
    YZEnforcedComposer public targetComposer;
    uint256 public reentrancyTarget;

    constructor(string memory _name, string memory _symbol, IERC20 _asset, address _composer, address _accessControl)
        YieldZeroVault(_name, _symbol, _asset, _composer, _accessControl)
    {}

    function setReentrancyTarget(address _composer, uint256 _targetFunction) external {
        targetComposer = YZEnforcedComposer(payable(_composer));
        reentrancyTarget = _targetFunction;
    }

    function deposit(uint256 assets, address receiver) public override returns (uint256) {
        if (reentrancyTarget == 1) {
            reentrancyTarget = 0; // prevent infinite loop
            targetComposer.depositAndSend(1 ether, _buildHopParam(address(0), address(this), 1, 1 ether), address(this));
        } else if (reentrancyTarget == 3) {
            reentrancyTarget = 0; // prevent infinite loop
            targetComposer.depositAndSend(1 ether, _buildHopParam(address(0), address(this), 1, 1 ether), address(this));
        }
        return super.deposit(assets, receiver);
    }

    function redeem(uint256 shares, address receiver, address owner) public override returns (uint256) {
        if (reentrancyTarget == 2) {
            reentrancyTarget = 0; // prevent infinite loop
            targetComposer.redeemAndSend(1 ether, _buildHopParam(address(0), address(this), 1, 1 ether), address(this));
        }
        return super.redeem(shares, receiver, owner);
    }

    function _buildHopParam(address, address user, uint32 dstEid, uint256 amount)
        internal
        pure
        returns (SendParam memory)
    {
        return SendParam({
            dstEid: dstEid,
            to: bytes32(uint256(uint160(user))),
            amountLD: amount,
            minAmountLD: amount,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });
    }
}
