// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import "../YieldZeroBaseTest.t.sol";
import "../../src/core/Strategy.sol";
import "forge-std/Test.sol";

contract MockStrategy is BaseStrategy {
    mapping(address => uint256) private _shares;
    uint256 private _totalAssets;
    uint256 private _totalShares;

    constructor(IERC20 underlyingAsset) BaseStrategy(underlyingAsset) {
        _totalAssets = 0;
        _totalShares = 0;
    }

    function deposit(uint256 assets, address receiver) external override returns (uint256 shares) {
        shares = assets;
        _shares[receiver] += shares;
        _totalShares += shares;
        _totalAssets += assets;

        emit StrategyDeposit(receiver, assets, shares);
        return shares;
    }

    function redeem(uint256 shares, address receiver, address owner) external override returns (uint256 assets) {
        assets = shares;
        _shares[owner] -= shares;
        _totalShares -= shares;
        _totalAssets -= assets;

        emit StrategyRedeem(owner, shares, assets);
        return assets;
    }

    function harvest() external override returns (uint256 yield) {
        yield = 100;
        _totalAssets += yield;
        emit StrategyHarvest(msg.sender, yield);
        return yield;
    }

    function totalAssets() external view override returns (uint256) {
        return _totalAssets;
    }

    function convertToAssets(uint256 shares) external view override returns (uint256) {
        return shares;
    }

    function convertToShares(uint256 assets) external view override returns (uint256) {
        return assets;
    }

    function getShares(address account) external view returns (uint256) {
        return _shares[account];
    }

    function getTotalShares() external view returns (uint256) {
        return _totalShares;
    }
}

contract StrategyTest is YieldZeroBaseTest {
    MockStrategy public mockStrategy;

    function setUp() public virtual override {
        super.setUp();
        mockStrategy = new MockStrategy(IERC20(address(assetOFT_arb)));

        vm.label(address(mockStrategy), "MockStrategy");
    }

    function test_strategy_initialization() public {
        assertEq(address(mockStrategy.asset()), address(assetOFT_arb));
        assertEq(mockStrategy.totalAssets(), 0);
    }

    function test_strategy_deposit() public {
        uint256 depositAmount = 100 ether;
        _fundLocalFromHub(address(this), depositAmount);
        assetOFT_arb.approve(address(mockStrategy), depositAmount);

        vm.expectEmit(true, true, false, true);
        emit StrategyDeposit(address(this), depositAmount, depositAmount);

        uint256 shares = mockStrategy.deposit(depositAmount, address(this));

        assertEq(shares, depositAmount);
        assertEq(mockStrategy.getShares(address(this)), depositAmount);
        assertEq(mockStrategy.totalAssets(), depositAmount);
        assertEq(mockStrategy.getTotalShares(), depositAmount);
    }

    function test_strategy_redeem() public {
        uint256 depositAmount = 100 ether;
        _fundLocalFromHub(address(this), depositAmount);
        assetOFT_arb.approve(address(mockStrategy), depositAmount);
        mockStrategy.deposit(depositAmount, address(this));

        vm.expectEmit(true, true, false, true);
        emit StrategyRedeem(address(this), depositAmount, depositAmount);

        uint256 assets = mockStrategy.redeem(depositAmount, address(this), address(this));

        assertEq(assets, depositAmount);
        assertEq(mockStrategy.getShares(address(this)), 0);
        assertEq(mockStrategy.totalAssets(), 0);
        assertEq(mockStrategy.getTotalShares(), 0);
    }

    function test_strategy_harvest() public {
        vm.expectEmit(true, true, false, true);
        emit StrategyHarvest(address(this), 100);

        uint256 yield = mockStrategy.harvest();
        assertEq(yield, 100);
        assertEq(mockStrategy.totalAssets(), 100);
    }

    function test_strategy_conversion_functions() public {
        assertEq(mockStrategy.convertToAssets(100), 100);
        assertEq(mockStrategy.convertToShares(100), 100);
        assertEq(mockStrategy.convertToAssets(0), 0);
        assertEq(mockStrategy.convertToShares(0), 0);
    }

    function test_strategy_multiple_deposits() public {
        _fundLocalFromHub(address(this), 100 ether);
        assetOFT_arb.approve(address(mockStrategy), 100 ether);

        mockStrategy.deposit(50 ether, address(this));
        mockStrategy.deposit(50 ether, address(this));

        assertEq(mockStrategy.getShares(address(this)), 100 ether);
        assertEq(mockStrategy.totalAssets(), 100 ether);
    }

    function test_strategy_partial_redeem() public {
        _fundLocalFromHub(address(this), 100 ether);
        assetOFT_arb.approve(address(mockStrategy), 100 ether);
        mockStrategy.deposit(100 ether, address(this));

        mockStrategy.redeem(50 ether, address(this), address(this));

        assertEq(mockStrategy.getShares(address(this)), 50 ether);
        assertEq(mockStrategy.totalAssets(), 50 ether);
    }

    event StrategyDeposit(address indexed user, uint256 assets, uint256 shares);
    event StrategyRedeem(address indexed user, uint256 shares, uint256 assets);
    event StrategyHarvest(address indexed harvester, uint256 yield);
}
