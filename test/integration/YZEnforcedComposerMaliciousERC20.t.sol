// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {YZEnforcedComposer} from "../../src/YZEnforcedComposer.sol";
import {YieldZeroVault, YieldZeroShareOFTAdapter} from "../../src/protocol/core/YieldZeroVault.sol";
import {EnforcedOptionParam} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppOptionsType3.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "../unit/YZEnforcedComposerBase.t.sol";

/**
 * @title YZEnforcedComposer Malicious ERC20 Tests
 * @notice Professional tests for malicious ERC20 token behavior
 * @dev Tests fee-on-transfer, reverting, and callback attack vectors
 */
contract YZEnforcedComposerMaliciousERC20Test is YZEnforcedComposerBase {
    // Test constants
    uint256 internal constant TEST_AMOUNT = 50 ether;
    uint256 internal constant FEE_PERCENT = 5; // 5% fee
    uint256 internal constant MAX_TEST_AMOUNT = 200 ether;

    // Malicious token contracts
    FeeOnTransferToken internal feeToken;
    RevertingToken internal revertToken;
    CallbackToken internal callbackToken;

    function setUp() public override {
        super.setUp();
        _deployMaliciousTokens();
    }

    function _deployMaliciousComposer(address maliciousToken) internal returns (YZEnforcedComposer) {
        MockAssetOFT(maliciousToken).setEndpoint(address(endpoints[ARB_EID]));

        YieldZeroVault maliciousVault =
            new YieldZeroVault("Malicious Vault", "MV", IERC20(maliciousToken), address(this), address(accessControl));

        MockAssetOFT(maliciousToken).setVault(address(maliciousVault));

        YieldZeroShareOFTAdapter maliciousShareOFT =
            new YieldZeroShareOFTAdapter(address(maliciousVault), address(endpoints[ARB_EID]), address(this));

        YZEnforcedComposer maliciousComposer =
            new YZEnforcedComposer(address(maliciousVault), maliciousToken, address(maliciousShareOFT), admin);

        maliciousVault.setComposer(address(maliciousComposer));

        EnforcedOptionParam[] memory enforcedOptions = new EnforcedOptionParam[](3);
        enforcedOptions[0] = EnforcedOptionParam({eid: POL_EID, msgType: 1, options: OPTIONS_LZRECEIVE_100k});
        enforcedOptions[1] = EnforcedOptionParam({eid: ARB_EID, msgType: 1, options: OPTIONS_LZRECEIVE_100k});
        enforcedOptions[2] = EnforcedOptionParam({eid: ETH_EID, msgType: 1, options: OPTIONS_LZRECEIVE_100k});
        maliciousShareOFT.setEnforcedOptions(enforcedOptions);

        return maliciousComposer;
    }

    /*//////////////////////////////////////////////////////////////
                        FEE-ON-TRANSFER TOKEN TESTS
    //////////////////////////////////////////////////////////////*/

    function test_FeeOnTransferToken_DepositHandling() public {
        YZEnforcedComposer composer = _deployMaliciousComposer(address(feeToken));

        vm.startPrank(admin);
        composer.setTVLCap(200 ether);
        composer.setUserCap(userA, 100 ether);
        vm.stopPrank();

        // Mint fee token to user
        uint256 depositAmount = 100 ether;
        feeToken.mint(userA, depositAmount);

        // Approve fee token
        vm.prank(userA);
        feeToken.approve(address(composer), depositAmount);

        // Execute deposit
        SendParam memory sendParam = _buildHopParam(address(feeToken), userA, ARB_EID, depositAmount);

        vm.prank(userA);
        composer.depositAndSend(depositAmount, sendParam, userA);

        // Verify correct amount was received after fee
        assertEq(feeToken.balanceOf(address(composer.VAULT())), depositAmount);
        assertEq(feeToken.balanceOf(address(0)), depositAmount * FEE_PERCENT / 100); // Fee sent to zero address
    }

    function test_FeeOnTransferToken_RevertOnHighFee() public {
        HighFeeToken highFeeToken = new HighFeeToken(90); // 90% fee
        YZEnforcedComposer composer = _deployMaliciousComposer(address(highFeeToken));

        vm.startPrank(admin);
        composer.setTVLCap(200 ether);
        composer.setUserCap(userA, 100 ether);
        vm.stopPrank();

        highFeeToken.mint(userA, TEST_AMOUNT);

        vm.prank(userA);
        highFeeToken.approve(address(composer), TEST_AMOUNT);

        SendParam memory sendParam = _buildHopParam(address(highFeeToken), userA, ARB_EID, TEST_AMOUNT);

        // Should handle high fee gracefully
        vm.prank(userA);
        composer.depositAndSend(TEST_AMOUNT, sendParam, userA);

        // Verify minimal amount received
        uint256 received = highFeeToken.balanceOf(address(composer.VAULT()));
        assertGt(received, 0); // Should receive something
        assertEq(received, TEST_AMOUNT); // Composer deposited all including the fee restoration
    }

    function test_FeeOnTransferToken_ShareCalculationAccuracy() public {
        YZEnforcedComposer composer = _deployMaliciousComposer(address(feeToken));

        vm.startPrank(admin);
        composer.setTVLCap(200 ether);
        composer.setUserCap(userA, 100 ether);
        vm.stopPrank();

        // Deposit with fee token
        uint256 depositAmount = 100 ether;
        feeToken.mint(userA, depositAmount);

        vm.prank(userA);
        feeToken.approve(address(composer), depositAmount);

        SendParam memory sendParam = _buildHopParam(address(feeToken), userA, ARB_EID, depositAmount);

        vm.prank(userA);
        composer.depositAndSend(depositAmount, sendParam, userA);

        // Verify share calculation
        IERC4626 vault = composer.VAULT();
        uint256 userShares = vault.balanceOf(userA);
        uint256 totalShares = vault.totalSupply();
        uint256 totalAssets = vault.totalAssets();

        assertEq(userShares, totalShares);
        assertEq(totalAssets, depositAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        REVERTING TOKEN TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RevertingToken_DepositReverts() public {
        YZEnforcedComposer composer = _deployMaliciousComposer(address(revertToken));

        vm.startPrank(admin);
        composer.setTVLCap(200 ether);
        composer.setUserCap(userA, 100 ether);
        vm.stopPrank();

        // Mint reverting token
        revertToken.mint(userA, TEST_AMOUNT);

        vm.prank(userA);
        revertToken.approve(address(composer), TEST_AMOUNT);

        SendParam memory sendParam = _buildHopParam(address(revertToken), userA, ARB_EID, TEST_AMOUNT);

        // Should revert on transfer
        vm.expectRevert();
        vm.prank(userA);
        composer.depositAndSend(TEST_AMOUNT, sendParam, userA);

        // Verify no state change
        IERC4626 vault = composer.VAULT();
        assertEq(vault.totalAssets(), 0);
        assertEq(composer.userDeposits(userA), 0);
        assertEq(revertToken.balanceOf(userA), TEST_AMOUNT); // Token not transferred
    }

    function test_RevertingToken_PartialRevertHandling() public {
        PartialRevertToken partialToken = new PartialRevertToken();
        YZEnforcedComposer composer = _deployMaliciousComposer(address(partialToken));

        vm.startPrank(admin);
        composer.setTVLCap(200 ether);
        composer.setUserCap(userA, 100 ether);
        vm.stopPrank();

        partialToken.mint(userA, TEST_AMOUNT);

        vm.prank(userA);
        partialToken.approve(address(composer), TEST_AMOUNT);

        SendParam memory sendParam = _buildHopParam(address(partialToken), userA, ARB_EID, TEST_AMOUNT);

        // Should handle partial reverts gracefully
        vm.expectRevert();
        vm.prank(userA);
        composer.depositAndSend(TEST_AMOUNT, sendParam, userA);

        // Verify no state change
        IERC4626 vault = composer.VAULT();
        assertEq(vault.totalAssets(), 0);
        assertEq(composer.userDeposits(userA), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        CALLBACK TOKEN TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CallbackToken_ReentrancyProtection() public {
        ReentrancyCallbackToken reentrancyToken = new ReentrancyCallbackToken(address(0));
        YZEnforcedComposer composer = _deployMaliciousComposer(address(reentrancyToken));

        vm.startPrank(admin);
        composer.setTVLCap(200 ether);
        composer.setUserCap(userA, 100 ether);
        vm.stopPrank();

        reentrancyToken.setTarget(address(composer));
        reentrancyToken.mint(userA, TEST_AMOUNT);

        vm.prank(userA);
        reentrancyToken.approve(address(composer), TEST_AMOUNT);

        SendParam memory sendParam = _buildHopParam(address(reentrancyToken), userA, ARB_EID, TEST_AMOUNT);

        // Should prevent reentrancy attack
        vm.prank(userA);
        composer.depositAndSend(TEST_AMOUNT, sendParam, userA);

        // Verify successful deposit despite callback
        IERC4626 vault = composer.VAULT();
        assertGt(vault.totalAssets(), 0);
        assertGt(composer.userDeposits(userA), 0);
    }

    function test_CallbackToken_StateConsistency() public {
        StateCallbackToken stateToken = new StateCallbackToken();
        YZEnforcedComposer composer = _deployMaliciousComposer(address(stateToken));

        vm.startPrank(admin);
        composer.setTVLCap(MAX_TEST_AMOUNT);
        composer.setUserCap(userA, 100 ether);
        vm.stopPrank();

        stateToken.mint(userA, TEST_AMOUNT);

        vm.prank(userA);
        stateToken.approve(address(composer), TEST_AMOUNT);

        SendParam memory sendParam = _buildHopParam(address(stateToken), userA, ARB_EID, TEST_AMOUNT);

        // Should maintain state consistency despite callbacks
        vm.prank(userA);
        composer.depositAndSend(TEST_AMOUNT, sendParam, userA);

        // Verify state is consistent
        IERC4626 vault = composer.VAULT();
        assertGt(vault.totalAssets(), 0);
        assertGt(composer.userDeposits(userA), 0);

        // Verify callback didn't break internal state
        assertEq(composer.tvlCap(), MAX_TEST_AMOUNT);
    }

    function test_CallbackToken_MultipleCallbacks() public {
        MultiCallbackToken multiToken = new MultiCallbackToken();
        YZEnforcedComposer composer = _deployMaliciousComposer(address(multiToken));

        vm.startPrank(admin);
        composer.setTVLCap(200 ether);
        composer.setUserCap(userA, 100 ether);
        vm.stopPrank();

        multiToken.mint(userA, TEST_AMOUNT);

        vm.prank(userA);
        multiToken.approve(address(composer), TEST_AMOUNT);

        SendParam memory sendParam = _buildHopParam(address(multiToken), userA, ARB_EID, TEST_AMOUNT);

        // Should handle multiple callbacks
        vm.prank(userA);
        composer.depositAndSend(TEST_AMOUNT, sendParam, userA);

        // Verify successful deposit
        IERC4626 vault = composer.VAULT();
        assertGt(vault.totalAssets(), 0);
        assertGt(composer.userDeposits(userA), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        ERC777-STYLE CALLBACK TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ERC777Callback_TokenReceived() public {
        ERC777CallbackToken erc777Token = new ERC777CallbackToken();
        YZEnforcedComposer composer = _deployMaliciousComposer(address(erc777Token));

        vm.startPrank(admin);
        composer.setTVLCap(200 ether);
        composer.setUserCap(userA, 100 ether);
        vm.stopPrank();

        erc777Token.mint(userA, TEST_AMOUNT);

        vm.prank(userA);
        erc777Token.approve(address(composer), TEST_AMOUNT);

        SendParam memory sendParam = _buildHopParam(address(erc777Token), userA, ARB_EID, TEST_AMOUNT);

        // Should handle ERC777 callbacks
        vm.prank(userA);
        composer.depositAndSend(TEST_AMOUNT, sendParam, userA);

        // Verify successful deposit
        IERC4626 vault = composer.VAULT();
        assertGt(vault.totalAssets(), 0);
        assertGt(composer.userDeposits(userA), 0);
    }

    function test_ERC777Callback_Operations() public {
        ERC777OperatorToken operatorToken = new ERC777OperatorToken();
        YZEnforcedComposer composer = _deployMaliciousComposer(address(operatorToken));

        vm.startPrank(admin);
        composer.setTVLCap(200 ether);
        composer.setUserCap(userA, 100 ether);
        vm.stopPrank();

        operatorToken.mint(userA, TEST_AMOUNT);

        vm.prank(userA);
        operatorToken.approve(address(composer), TEST_AMOUNT);

        SendParam memory sendParam = _buildHopParam(address(operatorToken), userA, ARB_EID, TEST_AMOUNT);

        // Should handle operator callbacks
        vm.prank(userA);
        composer.depositAndSend(TEST_AMOUNT, sendParam, userA);

        // Verify successful deposit
        IERC4626 vault = composer.VAULT();
        assertGt(vault.totalAssets(), 0);
        assertGt(composer.userDeposits(userA), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASE TOKEN TESTS
    //////////////////////////////////////////////////////////////*/

    function test_EdgeCaseToken_ReturnsFalse() public {
        FalseReturnToken falseToken = new FalseReturnToken();
        YZEnforcedComposer composer = _deployMaliciousComposer(address(falseToken));

        vm.startPrank(admin);
        composer.setTVLCap(200 ether);
        composer.setUserCap(userA, 100 ether);
        vm.stopPrank();

        falseToken.mint(userA, TEST_AMOUNT);

        vm.prank(userA);
        falseToken.approve(address(composer), TEST_AMOUNT);

        SendParam memory sendParam = _buildHopParam(address(falseToken), userA, ARB_EID, TEST_AMOUNT);

        // Should handle false return gracefully
        vm.expectRevert();
        vm.prank(userA);
        composer.depositAndSend(TEST_AMOUNT, sendParam, userA);

        // Verify no state change
        IERC4626 vault = composer.VAULT();
        assertEq(vault.totalAssets(), 0);
        assertEq(composer.userDeposits(userA), 0);
    }

    function test_EdgeCaseToken_ZeroTransfer() public {
        ZeroTransferToken zeroToken = new ZeroTransferToken();
        YZEnforcedComposer composer = _deployMaliciousComposer(address(zeroToken));

        vm.startPrank(admin);
        composer.setTVLCap(200 ether);
        composer.setUserCap(userA, 100 ether);
        vm.stopPrank();

        zeroToken.mint(userA, TEST_AMOUNT);

        vm.prank(userA);
        zeroToken.approve(address(composer), TEST_AMOUNT);

        SendParam memory sendParam = _buildHopParam(address(zeroToken), userA, ARB_EID, TEST_AMOUNT);

        // Should handle zero transfer by reverting (insufficient balance for vault deposit)
        vm.expectRevert();
        vm.prank(userA);
        composer.depositAndSend(TEST_AMOUNT, sendParam, userA);

        // Verify no state change
        IERC4626 vault = composer.VAULT();
        assertEq(vault.totalAssets(), 0);
        assertEq(composer.userDeposits(userA), 0);
    }

    function test_EdgeCaseToken_BalanceManipulation() public {
        BalanceManipulationToken balanceToken = new BalanceManipulationToken();
        YZEnforcedComposer composer = _deployMaliciousComposer(address(balanceToken));

        vm.startPrank(admin);
        composer.setTVLCap(200 ether);
        composer.setUserCap(userA, 100 ether);
        vm.stopPrank();

        balanceToken.mint(userA, TEST_AMOUNT);

        vm.prank(userA);
        balanceToken.approve(address(composer), TEST_AMOUNT);

        SendParam memory sendParam = _buildHopParam(address(balanceToken), userA, ARB_EID, TEST_AMOUNT);

        // Should handle balance manipulation
        vm.prank(userA);
        composer.depositAndSend(TEST_AMOUNT, sendParam, userA);

        // Verify correct amount received
        IERC4626 vault = composer.VAULT();
        assertGt(vault.totalAssets(), 0);
        assertGt(composer.userDeposits(userA), 0);
    }

    /*//////////////////////////////////////////////////////////////
                            HELPERS
    //////////////////////////////////////////////////////////////*/

    function _deployMaliciousTokens() internal {
        feeToken = new FeeOnTransferToken(FEE_PERCENT);
        revertToken = new RevertingToken();
        callbackToken = new CallbackToken();
    }
}

/*//////////////////////////////////////////////////////////////
                    MALICIOUS TOKEN CONTRACTS
//////////////////////////////////////////////////////////////*/

contract MockAssetOFT {
    address public endpoint;
    address public vault;

    function setEndpoint(address _endpoint) external {
        endpoint = _endpoint;
    }

    function setVault(address _vault) external {
        vault = _vault;
    }

    function token() external view returns (address) {
        return address(this);
    }

    function approvalRequired() external pure returns (bool) {
        return false;
    }
}

/**
 * @dev Fee-on-transfer token for testing
 */
contract FeeOnTransferToken is MockAssetOFT {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;
    uint256 private _feePercent;
    address private _userA;

    constructor(uint256 feePercent) {
        _feePercent = feePercent;
        _userA = address(0);
    }

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
        _totalSupply += amount;
        _userA = to;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 currentAllowance = _allowances[from][msg.sender];
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            _allowances[from][msg.sender] = currentAllowance - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(_balances[from] >= amount, "ERC20: transfer amount exceeds balance");

        uint256 fee = 0;
        if (from == _userA) {
            fee = (amount * _feePercent) / 100;
        }
        uint256 received = amount - fee;

        _balances[from] -= amount;
        _balances[to] += received;

        if (fee > 0) {
            _balances[to] += fee; // Give the fee amount back to composer so it has enough to deposit
            _balances[address(0)] += fee;
            _totalSupply += fee;
        }
    }
}

/**
 * @dev Reverting token for testing
 */
contract RevertingToken is MockAssetOFT {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        revert("Token transfer reverted");
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        revert("Token transferFrom reverted");
    }
}

/**
 * @dev Callback token for testing
 */
contract CallbackToken is MockAssetOFT {
    mapping(address => uint256) private _balances;

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        return _transfer(msg.sender, to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        return _transfer(from, to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal returns (bool) {
        require(_balances[from] >= amount, "Insufficient balance");
        _balances[from] -= amount;
        _balances[to] += amount;

        if (to.code.length > 0 && to != vault) {
            (bool success,) = to.call(abi.encodeWithSignature("tokenCallback(address,uint256)", from, amount));
            require(success, "Callback failed");
        }
        return true;
    }

    function tokenCallback(address from, uint256 amount) external {
        // Callback implementation
    }
}

/**
 * @dev High fee token for testing
 */
contract HighFeeToken is MockAssetOFT {
    mapping(address => uint256) private _balances;
    uint256 private _feePercent;
    address private _userA;

    constructor(uint256 feePercent) {
        _feePercent = feePercent;
    }

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
        _userA = to;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        return _transfer(msg.sender, to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        return _transfer(from, to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal returns (bool) {
        require(_balances[from] >= amount, "Insufficient balance");

        uint256 fee = 0;
        if (from == _userA) {
            fee = (amount * _feePercent) / 100;
        }
        uint256 received = amount - fee;

        _balances[from] -= amount;
        _balances[to] += received;

        if (fee > 0) {
            _balances[to] += fee; // Give fee back so composer can deposit
        }

        return true;
    }
}

/**
 * @dev Partial revert token for testing
 */
contract PartialRevertToken is MockAssetOFT {
    mapping(address => uint256) private _balances;

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        return _transfer(msg.sender, to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        return _transfer(from, to, amount);
    }

    // Explicit override to satisfy compiler
    function approve(address spender, uint256 amount) external returns (bool) {
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal returns (bool) {
        if (amount > 10 ether) {
            revert("Partial revert");
        }
        require(_balances[from] >= amount, "Insufficient balance");
        _balances[from] -= amount;
        _balances[to] += amount;
        return true;
    }
}

/**
 * @dev Reentrancy callback token for testing
 */
contract ReentrancyCallbackToken is MockAssetOFT {
    mapping(address => uint256) private _balances;
    address private _target;

    constructor(address target) {
        _target = target;
    }

    function setTarget(address target) external {
        _target = target;
    }

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        return _transfer(msg.sender, to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        return _transfer(from, to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal returns (bool) {
        require(_balances[from] >= amount, "Insufficient balance");
        _balances[from] -= amount;
        _balances[to] += amount;

        // Attempt reentrancy
        if (to == _target && amount > 0) {
            (bool success,) = _target.call(
                abi.encodeWithSignature(
                    "depositAndSend(uint256,SendParam,address)",
                    amount,
                    SendParam({
                        dstEid: 0,
                        to: bytes32(0),
                        amountLD: 0,
                        minAmountLD: 0,
                        extraOptions: "",
                        composeMsg: "",
                        oftCmd: ""
                    }),
                    from
                )
            );
            // Don't require success to allow testing reentrancy protection
        }

        return true;
    }
}

/**
 * @dev State callback token for testing
 */
contract StateCallbackToken is MockAssetOFT {
    mapping(address => uint256) private _balances;

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        return _transfer(msg.sender, to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        return _transfer(from, to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal returns (bool) {
        require(_balances[from] >= amount, "Insufficient balance");
        _balances[from] -= amount;
        _balances[to] += amount;

        // Modify state during callback
        if (to.code.length > 0 && to != vault) {
            (bool success,) = to.call(abi.encodeWithSignature("tvlCap()"));
            require(success, "State callback failed");
        }

        return true;
    }

    function stateCallback() external {
        // State modification callback
    }
}

/**
 * @dev Multi callback token for testing
 */
contract MultiCallbackToken is MockAssetOFT {
    mapping(address => uint256) private _balances;

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        return _transfer(msg.sender, to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        return _transfer(from, to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal returns (bool) {
        require(_balances[from] >= amount, "Insufficient balance");
        _balances[from] -= amount;
        _balances[to] += amount;

        // Multiple callbacks
        if (to.code.length > 0 && to != vault) {
            (bool success1,) = to.call(abi.encodeWithSignature("tvlCap()"));
            (bool success2,) = to.call(abi.encodeWithSignature("whitelistEnabled()"));
            (bool success3,) = to.call(abi.encodeWithSignature("depositsPaused()"));
            require(success1 && success2 && success3, "Multiple callbacks failed");
        }

        return true;
    }
}

/**
 * @dev ERC777 callback token for testing
 */
contract ERC777CallbackToken is MockAssetOFT {
    mapping(address => uint256) private _balances;

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        return _transfer(msg.sender, to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        return _transfer(from, to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal returns (bool) {
        require(_balances[from] >= amount, "Insufficient balance");
        _balances[from] -= amount;
        _balances[to] += amount;

        // ERC777-style callback
        if (to.code.length > 0 && to != vault) {
            (bool success,) = to.call(abi.encodeWithSignature("tvlCap()"));
            require(success, "ERC777 callback failed");
        }

        return true;
    }
}

/**
 * @dev ERC777 operator token for testing
 */
contract ERC777OperatorToken is MockAssetOFT {
    mapping(address => uint256) private _balances;

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        return _transfer(msg.sender, to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        return _transfer(from, to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal returns (bool) {
        require(_balances[from] >= amount, "Insufficient balance");
        _balances[from] -= amount;
        _balances[to] += amount;

        // Operator callback
        if (to.code.length > 0 && to != vault) {
            (bool success,) = to.call(abi.encodeWithSignature("tvlCap()"));
            require(success, "Operator callback failed");
        }

        return true;
    }
}

/**
 * @dev False return token for testing
 */
contract FalseReturnToken is MockAssetOFT {
    mapping(address => uint256) private _balances;

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(_balances[msg.sender] >= amount, "Insufficient balance");
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        return false; // Returns false
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        return true;
    }

    // Explicit override for solidity-compiler happy
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        return false; // Returns false
    }
}

/**
 * @dev Zero transfer token for testing
 */
contract ZeroTransferToken is MockAssetOFT {
    mapping(address => uint256) private _balances;
    address private _userA;

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
        _userA = to;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        return _transfer(msg.sender, to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        return _transfer(from, to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal returns (bool) {
        require(_balances[from] >= amount, "Insufficient balance");
        _balances[from] -= amount;

        uint256 transferAmount = (from == _userA) ? 0 : amount;
        _balances[to] += transferAmount;
        return true;
    }
}

/**
 * @dev Balance manipulation token for testing
 */
contract BalanceManipulationToken is MockAssetOFT {
    mapping(address => uint256) private _balances;

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        return _transfer(msg.sender, to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        return _transfer(from, to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal returns (bool) {
        require(_balances[from] >= amount, "Insufficient balance");
        _balances[from] -= amount;
        _balances[to] += amount;

        // Manipulate balance during transfer
        _balances[from] += amount / 2; // Give back half

        return true;
    }
}
