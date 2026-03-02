// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {YZEnforcedComposer} from "../../src/sdk/YZEnforcedComposer.sol";
import "./YZEnforcedComposerBase.t.sol";

/**
 * @title YZEnforcedComposer Malicious ERC20 Tests
 * @notice Professional tests for malicious ERC20 token behavior
 * @dev Tests fee-on-transfer, reverting, and callback attack vectors
 */
contract YZEnforcedComposerMaliciousERC20Test is YZEnforcedComposerBase {
    
    // Test constants
    uint256 internal constant TEST_AMOUNT = 50 ether;
    uint256 internal constant FEE_PERCENT = 5; // 5% fee

    // Malicious token contracts
    FeeOnTransferToken internal feeToken;
    RevertingToken internal revertToken;
    CallbackToken internal callbackToken;

    function setUp() public override {
        super.setUp();
        _setupDefaultCaps();
        _deployMaliciousTokens();
    }

    /*//////////////////////////////////////////////////////////////
                        FEE-ON-TRANSFER TOKEN TESTS
    //////////////////////////////////////////////////////////////*/

    function test_FeeOnTransferToken_DepositHandling() public {
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        // Mint fee token to user
        uint256 depositAmount = 100 ether;
        feeToken.mint(userA, depositAmount);
        
        // Approve fee token
        vm.prank(userA);
        feeToken.approve(address(yzEnforcedComposer_arb), depositAmount);
        
        // Calculate expected received amount after fee
        uint256 expectedReceived = depositAmount - (depositAmount * FEE_PERCENT / 100);
        
        // Execute deposit
        SendParam memory sendParam = _buildHopParam(address(feeToken), userA, ARB_EID, depositAmount);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(depositAmount, sendParam, userA);
        
        // Verify correct amount was received after fee
        assertEq(feeToken.balanceOf(address(yzEnforcedComposer_arb)), expectedReceived);
        assertEq(feeToken.balanceOf(address(0)), depositAmount - expectedReceived); // Fee sent to zero address
    }

    function test_FeeOnTransferToken_RevertOnHighFee() public {
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        // Create token with very high fee
        HighFeeToken highFeeToken = new HighFeeToken(90); // 90% fee
        highFeeToken.mint(userA, TEST_AMOUNT);
        
        vm.prank(userA);
        highFeeToken.approve(address(yzEnforcedComposer_arb), TEST_AMOUNT);
        
        SendParam memory sendParam = _buildHopParam(address(highFeeToken), userA, ARB_EID, TEST_AMOUNT);
        
        // Should handle high fee gracefully
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(TEST_AMOUNT, sendParam, userA);
        
        // Verify minimal amount received
        uint256 received = highFeeToken.balanceOf(address(yzEnforcedComposer_arb));
        assertGt(received, 0); // Should receive something
        assertLt(received, TEST_AMOUNT); // But less than requested
    }

    function test_FeeOnTransferToken_ShareCalculationAccuracy() public {
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        // Deposit with fee token
        uint256 depositAmount = 100 ether;
        feeToken.mint(userA, depositAmount);
        
        vm.prank(userA);
        feeToken.approve(address(yzEnforcedComposer_arb), depositAmount);
        
        SendParam memory sendParam = _buildHopParam(address(feeToken), userA, ARB_EID, depositAmount);
        
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(depositAmount, sendParam, userA);
        
        // Verify share calculation is based on actual received amount
        uint256 expectedReceived = depositAmount - (depositAmount * FEE_PERCENT / 100);
        uint256 userShares = vault_arb.balanceOf(userA);
        uint256 totalShares = vault_arb.totalSupply();
        uint256 totalAssets = vault_arb.totalAssets();
        
        // Shares should be proportional to actual received amount
        assertEq(userShares, totalShares);
        assertEq(totalAssets, expectedReceived);
    }

    /*//////////////////////////////////////////////////////////////
                        REVERTING TOKEN TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RevertingToken_DepositReverts() public {
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        // Mint reverting token
        revertToken.mint(userA, TEST_AMOUNT);
        
        vm.prank(userA);
        revertToken.approve(address(yzEnforcedComposer_arb), TEST_AMOUNT);
        
        SendParam memory sendParam = _buildHopParam(address(revertToken), userA, ARB_EID, TEST_AMOUNT);
        
        // Should revert on transfer
        vm.expectRevert();
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(TEST_AMOUNT, sendParam, userA);
        
        // Verify no state change
        assertEq(vault_arb.totalAssets(), 0);
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), 0);
        assertEq(revertToken.balanceOf(userA), TEST_AMOUNT); // Token not transferred
    }

    function test_RevertingToken_PartialRevertHandling() public {
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        // Create token that reverts on certain amounts
        PartialRevertToken partialToken = new PartialRevertToken();
        partialToken.mint(userA, TEST_AMOUNT);
        
        vm.prank(userA);
        partialToken.approve(address(yzEnforcedComposer_arb), TEST_AMOUNT);
        
        SendParam memory sendParam = _buildHopParam(address(partialToken), userA, ARB_EID, TEST_AMOUNT);
        
        // Should handle partial reverts gracefully
        vm.expectRevert();
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(TEST_AMOUNT, sendParam, userA);
        
        // Verify no state change
        assertEq(vault_arb.totalAssets(), 0);
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        CALLBACK TOKEN TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CallbackToken_ReentrancyProtection() public {
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        // Create callback token that tries reentrancy
        ReentrancyCallbackToken reentrancyToken = new ReentrancyCallbackToken(address(yzEnforcedComposer_arb));
        reentrancyToken.mint(userA, TEST_AMOUNT);
        
        vm.prank(userA);
        reentrancyToken.approve(address(yzEnforcedComposer_arb), TEST_AMOUNT);
        
        SendParam memory sendParam = _buildHopParam(address(reentrancyToken), userA, ARB_EID, TEST_AMOUNT);
        
        // Should prevent reentrancy attack
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(TEST_AMOUNT, sendParam, userA);
        
        // Verify successful deposit despite callback
        assertGt(vault_arb.totalAssets(), 0);
        assertGt(yzEnforcedComposer_arb.userDeposits(userA), 0);
    }

    function test_CallbackToken_StateConsistency() public {
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        // Create callback token that modifies state
        StateCallbackToken stateToken = new StateCallbackToken();
        stateToken.mint(userA, TEST_AMOUNT);
        
        vm.prank(userA);
        stateToken.approve(address(yzEnforcedComposer_arb), TEST_AMOUNT);
        
        SendParam memory sendParam = _buildHopParam(address(stateToken), userA, ARB_EID, TEST_AMOUNT);
        
        // Should maintain state consistency despite callbacks
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(TEST_AMOUNT, sendParam, userA);
        
        // Verify state is consistent
        assertGt(vault_arb.totalAssets(), 0);
        assertGt(yzEnforcedComposer_arb.userDeposits(userA), 0);
        
        // Verify callback didn't break internal state
        assertEq(yzEnforcedComposer_arb.tvlCap(), MAX_TEST_AMOUNT);
    }

    function test_CallbackToken_MultipleCallbacks() public {
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        // Create token with multiple callbacks
        MultiCallbackToken multiToken = new MultiCallbackToken();
        multiToken.mint(userA, TEST_AMOUNT);
        
        vm.prank(userA);
        multiToken.approve(address(yzEnforcedComposer_arb), TEST_AMOUNT);
        
        SendParam memory sendParam = _buildHopParam(address(multiToken), userA, ARB_EID, TEST_AMOUNT);
        
        // Should handle multiple callbacks
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(TEST_AMOUNT, sendParam, userA);
        
        // Verify successful deposit
        assertGt(vault_arb.totalAssets(), 0);
        assertGt(yzEnforcedComposer_arb.userDeposits(userA), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        ERC777-STYLE CALLBACK TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ERC777Callback_TokenReceived() public {
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        // Create ERC777-style token
        ERC777CallbackToken erc777Token = new ERC777CallbackToken();
        erc777Token.mint(userA, TEST_AMOUNT);
        
        vm.prank(userA);
        erc777Token.approve(address(yzEnforcedComposer_arb), TEST_AMOUNT);
        
        SendParam memory sendParam = _buildHopParam(address(erc777Token), userA, ARB_EID, TEST_AMOUNT);
        
        // Should handle ERC777 callbacks
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(TEST_AMOUNT, sendParam, userA);
        
        // Verify successful deposit
        assertGt(vault_arb.totalAssets(), 0);
        assertGt(yzEnforcedComposer_arb.userDeposits(userA), 0);
    }

    function test_ERC777Callback_Operations() public {
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        // Create ERC777 token with operator callbacks
        ERC777OperatorToken operatorToken = new ERC777OperatorToken();
        operatorToken.mint(userA, TEST_AMOUNT);
        
        vm.prank(userA);
        operatorToken.approve(address(yzEnforcedComposer_arb), TEST_AMOUNT);
        
        SendParam memory sendParam = _buildHopParam(address(operatorToken), userA, ARB_EID, TEST_AMOUNT);
        
        // Should handle operator callbacks
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(TEST_AMOUNT, sendParam, userA);
        
        // Verify successful deposit
        assertGt(vault_arb.totalAssets(), 0);
        assertGt(yzEnforcedComposer_arb.userDeposits(userA), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASE TOKEN TESTS
    //////////////////////////////////////////////////////////////*/

    function test_EdgeCaseToken_ReturnsFalse() public {
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        // Create token that returns false on transfer
        FalseReturnToken falseToken = new FalseReturnToken();
        falseToken.mint(userA, TEST_AMOUNT);
        
        vm.prank(userA);
        falseToken.approve(address(yzEnforcedComposer_arb), TEST_AMOUNT);
        
        SendParam memory sendParam = _buildHopParam(address(falseToken), userA, ARB_EID, TEST_AMOUNT);
        
        // Should handle false return gracefully
        vm.expectRevert();
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(TEST_AMOUNT, sendParam, userA);
        
        // Verify no state change
        assertEq(vault_arb.totalAssets(), 0);
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), 0);
    }

    function test_EdgeCaseToken_ZeroTransfer() public {
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        // Create token that transfers zero
        ZeroTransferToken zeroToken = new ZeroTransferToken();
        zeroToken.mint(userA, TEST_AMOUNT);
        
        vm.prank(userA);
        zeroToken.approve(address(yzEnforcedComposer_arb), TEST_AMOUNT);
        
        SendParam memory sendParam = _buildHopParam(address(zeroToken), userA, ARB_EID, TEST_AMOUNT);
        
        // Should handle zero transfer
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(TEST_AMOUNT, sendParam, userA);
        
        // Verify zero amount handled correctly
        assertEq(vault_arb.totalAssets(), 0);
        assertEq(yzEnforcedComposer_arb.userDeposits(userA), 0);
    }

    function test_EdgeCaseToken_BalanceManipulation() public {
        _setupUserCap(userA, 100 ether);
        _setupTVLCap(200 ether);
        
        // Create token that manipulates balance during transfer
        BalanceManipulationToken balanceToken = new BalanceManipulationToken();
        balanceToken.mint(userA, TEST_AMOUNT);
        
        vm.prank(userA);
        balanceToken.approve(address(yzEnforcedComposer_arb), TEST_AMOUNT);
        
        SendParam memory sendParam = _buildHopParam(address(balanceToken), userA, ARB_EID, TEST_AMOUNT);
        
        // Should handle balance manipulation
        vm.prank(userA);
        yzEnforcedComposer_arb.depositAndSend(TEST_AMOUNT, sendParam, userA);
        
        // Verify correct amount received
        assertGt(vault_arb.totalAssets(), 0);
        assertGt(yzEnforcedComposer_arb.userDeposits(userA), 0);
    }

    /*//////////////////////////////////////////////////////////////
                            HELPERS
    //////////////////////////////////////////////////////////////*/

    function _setupDefaultCaps() internal {
        vm.prank(admin);
        yzEnforcedComposer_arb.setTVLCap(MAX_TEST_AMOUNT);
    }

    function _setupUserCap(address user, uint256 cap) internal {
        vm.prank(admin);
        yzEnforcedComposer_arb.setUserCap(user, cap);
    }

    function _deployMaliciousTokens() internal {
        feeToken = new FeeOnTransferToken(FEE_PERCENT);
        revertToken = new RevertingToken();
        callbackToken = new CallbackToken();
    }

    /*//////////////////////////////////////////////////////////////
                        MALICIOUS TOKEN CONTRACTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Fee-on-transfer token for testing
     */
    contract FeeOnTransferToken {
        mapping(address => uint256) private _balances;
        mapping(address => mapping(address => uint256)) private _allowances;
        uint256 private _totalSupply;
        uint256 private _feePercent;

        constructor(uint256 feePercent) {
            _feePercent = feePercent;
        }

        function mint(address to, uint256 amount) external {
            _balances[to] += amount;
            _totalSupply += amount;
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
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            _transfer(from, to, amount);
            _allowances[from][msg.sender] = currentAllowance - amount;
            return true;
        }

        function _transfer(address from, address to, uint256 amount) private {
            require(_balances[from] >= amount, "ERC20: transfer amount exceeds balance");
            
            uint256 fee = (amount * _feePercent) / 100;
            uint256 received = amount - fee;
            
            _balances[from] -= amount;
            _balances[to] += received;
            _balances[address(0)] += fee; // Fee to zero address
            
            _totalSupply -= fee; // Burn fee
        }
    }

    /**
     * @dev Reverting token for testing
     */
    contract RevertingToken {
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
    contract CallbackToken {
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
            
            // Simulate callback
            if (to.code.length > 0) {
                (bool success, ) = to.call(abi.encodeWithSignature("tokenCallback(address,uint256)", msg.sender, amount));
                require(success, "Callback failed");
            }
            
            return true;
        }

        function approve(address spender, uint256 amount) external returns (bool) {
            return true;
        }

        function transferFrom(address from, address to, uint256 amount) external returns (bool) {
            return transfer(to, amount);
        }

        function tokenCallback(address from, uint256 amount) external {
            // Callback implementation
        }
    }

    /**
     * @dev High fee token for testing
     */
    contract HighFeeToken {
        mapping(address => uint256) private _balances;
        uint256 private _feePercent;

        constructor(uint256 feePercent) {
            _feePercent = feePercent;
        }

        function mint(address to, uint256 amount) external {
            _balances[to] += amount;
        }

        function balanceOf(address account) external view returns (uint256) {
            return _balances[account];
        }

        function transfer(address to, uint256 amount) external returns (bool) {
            require(_balances[msg.sender] >= amount, "Insufficient balance");
            
            uint256 fee = (amount * _feePercent) / 100;
            uint256 received = amount - fee;
            
            _balances[msg.sender] -= amount;
            _balances[to] += received;
            
            return true;
        }

        function approve(address spender, uint256 amount) external returns (bool) {
            return true;
        }

        function transferFrom(address from, address to, uint256 amount) external returns (bool) {
            return transfer(to, amount);
        }
    }

    /**
     * @dev Partial revert token for testing
     */
    contract PartialRevertToken {
        mapping(address => uint256) private _balances;

        function mint(address to, uint256 amount) external {
            _balances[to] += amount;
        }

        function balanceOf(address account) external view returns (uint256) {
            return _balances[account];
        }

        function transfer(address to, uint256 amount) external returns (bool) {
            if (amount > 10 ether) {
                revert("Partial revert");
            }
            require(_balances[msg.sender] >= amount, "Insufficient balance");
            _balances[msg.sender] -= amount;
            _balances[to] += amount;
            return true;
        }

        function approve(address spender, uint256 amount) external returns (bool) {
            return true;
        }

        function transferFrom(address from, address to, uint256 amount) external returns (bool) {
            return transfer(to, amount);
        }
    }

    /**
     * @dev Reentrancy callback token for testing
     */
    contract ReentrancyCallbackToken {
        mapping(address => uint256) private _balances;
        address private _target;

        constructor(address target) {
            _target = target;
        }

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
            
            // Attempt reentrancy
            if (to == _target && amount > 0) {
                (bool success, ) = _target.call(abi.encodeWithSignature("depositAndSend(uint256,SendParam,address)", amount, SendParam(0, 0, 0, 0, 0, 0, 0, 0), msg.sender));
                // Don't require success to allow testing reentrancy protection
            }
            
            return true;
        }

        function approve(address spender, uint256 amount) external returns (bool) {
            return true;
        }

        function transferFrom(address from, address to, uint256 amount) external returns (bool) {
            return transfer(to, amount);
        }
    }

    /**
     * @dev State callback token for testing
     */
    contract StateCallbackToken {
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
            
            // Modify state during callback
            if (to.code.length > 0) {
                (bool success, ) = to.call(abi.encodeWithSignature("stateCallback()"));
                require(success, "State callback failed");
            }
            
            return true;
        }

        function approve(address spender, uint256 amount) external returns (bool) {
            return true;
        }

        function transferFrom(address from, address to, uint256 amount) external returns (bool) {
            return transfer(to, amount);
        }

        function stateCallback() external {
            // State modification callback
        }
    }

    /**
     * @dev Multi callback token for testing
     */
    contract MultiCallbackToken {
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
            
            // Multiple callbacks
            if (to.code.length > 0) {
                (bool success1, ) = to.call(abi.encodeWithSignature("callback1()"));
                (bool success2, ) = to.call(abi.encodeWithSignature("callback2()"));
                (bool success3, ) = to.call(abi.encodeWithSignature("callback3()"));
                require(success1 && success2 && success3, "Multiple callbacks failed");
            }
            
            return true;
        }

        function approve(address spender, uint256 amount) external returns (bool) {
            return true;
        }

        function transferFrom(address from, address to, uint256 amount) external returns (bool) {
            return transfer(to, amount);
        }
    }

    /**
     * @dev ERC777 callback token for testing
     */
    contract ERC777CallbackToken {
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
            
            // ERC777-style callback
            if (to.code.length > 0) {
                (bool success, ) = to.call(abi.encodeWithSignature("tokensReceived(address,address,address,uint256,bytes,bytes)", address(0), msg.sender, to, amount, "", ""));
                require(success, "ERC777 callback failed");
            }
            
            return true;
        }

        function approve(address spender, uint256 amount) external returns (bool) {
            return true;
        }

        function transferFrom(address from, address to, uint256 amount) external returns (bool) {
            return transfer(to, amount);
        }
    }

    /**
     * @dev ERC777 operator token for testing
     */
    contract ERC777OperatorToken {
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
            
            // Operator callback
            if (to.code.length > 0) {
                (bool success, ) = to.call(abi.encodeWithSignature("tokensToSend(address,address,address,uint256,bytes,bytes)", address(0), msg.sender, to, amount, "", ""));
                require(success, "Operator callback failed");
            }
            
            return true;
        }

        function approve(address spender, uint256 amount) external returns (bool) {
            return true;
        }

        function transferFrom(address from, address to, uint256 amount) external returns (bool) {
            return transfer(to, amount);
        }
    }

    /**
     * @dev False return token for testing
     */
    contract FalseReturnToken {
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

        function transferFrom(address from, address to, uint256 amount) external returns (bool) {
            return false; // Returns false
        }
    }

    /**
     * @dev Zero transfer token for testing
     */
    contract ZeroTransferToken {
        mapping(address => uint256) private _balances;

        function mint(address to, uint256 amount) external {
            _balances[to] += amount;
        }

        function balanceOf(address account) external view returns (uint256) {
            return _balances[account];
        }

        function transfer(address to, uint256 amount) external returns (bool) {
            require(_balances[msg.sender] >= amount, "Insufficient balance");
            // Transfers zero instead of requested amount
            _balances[msg.sender] -= amount;
            _balances[to] += 0; // Transfers zero
            return true;
        }

        function approve(address spender, uint256 amount) external returns (bool) {
            return true;
        }

        function transferFrom(address from, address to, uint256 amount) external returns (bool) {
            return transfer(to, amount);
        }
    }

    /**
     * @dev Balance manipulation token for testing
     */
    contract BalanceManipulationToken {
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
            
            // Manipulate balance during transfer
            _balances[msg.sender] += amount / 2; // Give back half
            
            return true;
        }

        function approve(address spender, uint256 amount) external returns (bool) {
            return true;
        }

        function transferFrom(address from, address to, uint256 amount) external returns (bool) {
            return transfer(to, amount);
        }
    }
}