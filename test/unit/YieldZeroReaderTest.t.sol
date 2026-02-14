// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import "../YieldZeroBaseTest.t.sol";
import "../../src/read/YieldZeroReader.sol";
import "../../src/errors/Errors.sol";
import "forge-std/Test.sol";

contract MockVault is IVault {
    uint256 public _totalAssets;
    uint256 public _totalSupply;
    mapping(address => uint256) public balances;

    function setTotalAssets(uint256 _assets) external {
        _totalAssets = _assets;
    }

    function setTotalSupply(uint256 _supply) external {
        _totalSupply = _supply;
    }

    function setBalance(address user, uint256 amount) external {
        balances[user] = amount;
    }

    function totalAssets() external view returns (uint256) {
        return _totalAssets;
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }

    function convertToAssets(uint256 shares) external view returns (uint256) {
        if (_totalSupply == 0 || _totalAssets == 0) {
            return shares;
        }
        return (shares * _totalAssets) / _totalSupply;
    }

    function convertToShares(uint256 assets) external view returns (uint256) {
        if (_totalAssets == 0 || _totalSupply == 0) {
            return assets;
        }
        return (assets * _totalSupply) / _totalAssets;
    }
}

contract MockComposer is IComposer {
    uint256 public tvl;
    mapping(address => uint256) public userShares;
    mapping(address => uint256) public userAssets;

    function setTVL(uint256 _tvl) external {
        tvl = _tvl;
    }

    function setUserShares(address user, uint256 shares) external {
        userShares[user] = shares;
    }

    function setUserAssets(address user, uint256 assets) external {
        userAssets[user] = assets;
    }

    function getTotalValueLocked() external view returns (uint256) {
        return tvl;
    }

    function getUserShares(address user) external view returns (uint256) {
        return userShares[user];
    }

    function getUserAssets(address user) external view returns (uint256) {
        return userAssets[user];
    }
}

contract MockHub is IHub {
    bool public paused;
    uint256 public _feeBasisPoints;
    uint256 public totalFees;
    uint256 public lastHarvest;

    function setPaused(bool _paused) external {
        paused = _paused;
    }

    function setFeeBasisPoints(uint256 _fees) external {
        _feeBasisPoints = _fees;
    }

    function setTotalFees(uint256 _fees) external {
        totalFees = _fees;
    }

    function setLastHarvest(uint256 timestamp) external {
        lastHarvest = timestamp;
    }

    function isPaused() external view returns (bool) {
        return paused;
    }

    function feeBasisPoints() external view returns (uint256) {
        return _feeBasisPoints;
    }

    function totalFeesCollected() external view returns (uint256) {
        return totalFees;
    }

    function lastHarvestTime() external view returns (uint256) {
        return lastHarvest;
    }
}

contract YieldZeroReaderTest is YieldZeroBaseTest {
    YieldZeroReader public reader;
    MockVault public mockVault;
    MockComposer public mockComposer;
    MockHub public mockHub;
    address public asset;

    address public user = makeAddr("user");

    function setUp() public virtual override {
        super.setUp();

        asset = address(assetOFT_arb);
        mockVault = new MockVault();
        mockComposer = new MockComposer();
        mockHub = new MockHub();

        reader = new YieldZeroReader(address(mockVault), address(mockComposer), address(mockHub), asset);

        vm.label(address(reader), "YieldZeroReader");
        vm.label(address(mockVault), "MockVault");
        vm.label(address(mockComposer), "MockComposer");
        vm.label(address(mockHub), "MockHub");
        vm.label(user, "User");
    }

    function test_initialization() public {
        assertEq(reader.vault(), address(mockVault));
        assertEq(reader.composer(), address(mockComposer));
        assertEq(reader.hub(), address(mockHub));
        assertEq(reader.asset(), asset);
    }

    function test_set_vault_address() public {
        MockVault newVault = new MockVault();
        reader.setVaultAddress(address(newVault));
        assertEq(reader.vault(), address(newVault));
    }

    function test_set_composer_address() public {
        MockComposer newComposer = new MockComposer();
        reader.setComposerAddress(address(newComposer));
        assertEq(reader.composer(), address(newComposer));
    }

    function test_set_hub_address() public {
        MockHub newHub = new MockHub();
        reader.setHubAddress(address(newHub));
        assertEq(reader.hub(), address(newHub));
    }

    function test_cannot_set_zero_address() public {
        vm.expectRevert(YZReader_InvalidAddress.selector);
        reader.setVaultAddress(address(0));

        vm.expectRevert(YZReader_InvalidAddress.selector);
        reader.setComposerAddress(address(0));

        vm.expectRevert(YZReader_InvalidAddress.selector);
        reader.setHubAddress(address(0));
    }

    function test_get_total_value_locked() public {
        uint256 expectedTVL = 1000 ether;
        mockComposer.setTVL(expectedTVL);
        assertEq(reader.getTotalValueLocked(), expectedTVL);
    }

    function test_get_user_total_shares() public {
        uint256 expectedShares = 500 ether;
        mockComposer.setUserShares(user, expectedShares);
        assertEq(reader.getUserTotalShares(user), expectedShares);
    }

    function test_get_user_total_assets() public {
        uint256 expectedAssets = 250 ether;
        mockComposer.setUserAssets(user, expectedAssets);
        assertEq(reader.getUserTotalAssets(user), expectedAssets);
    }

    function test_get_exchange_rate() public {
        mockVault.setTotalAssets(1000 ether);
        mockVault.setTotalSupply(1050 ether);
        uint256 rate = reader.getExchangeRate();

        assertEq(rate, (1050 ether * 1e18) / 1000 ether);
    }

    function test_get_exchange_rate_initial() public {
        mockVault.setTotalAssets(0);
        mockVault.setTotalSupply(0);
        assertEq(reader.getExchangeRate(), 1e18);
    }

    function test_get_vault_status() public {
        mockHub.setPaused(false);
        mockVault.setTotalAssets(1000 ether);
        mockVault.setTotalSupply(1050 ether);
        mockComposer.setTVL(1000 ether);

        (bool paused, uint256 totalAssets, uint256 totalShares, uint256 tvl) = reader.getVaultStatus();

        assertFalse(paused);
        assertEq(totalAssets, 1000 ether);
        assertEq(totalShares, 1050 ether);
        assertEq(tvl, 1000 ether);
    }

    function test_conversion_functions() public {
        mockVault.setTotalAssets(1000 ether);
        mockVault.setTotalSupply(1050 ether);

        uint256 shares = reader.convertToShares(100 ether);
        assertEq(shares, (100 ether * 1050 ether) / 1000 ether);

        uint256 assets = reader.convertToAssets(105 ether);
        assertEq(assets, (105 ether * 1000 ether) / 1050 ether);
    }

    function test_user_balance_in_assets() public {
        mockVault.setTotalAssets(1000 ether);
        mockVault.setTotalSupply(1050 ether);
        mockVault.setBalance(user, 105 ether);

        uint256 assets = reader.getUserBalanceInAssets(user);
        assertEq(assets, 100 ether);
    }

    function test_get_vault_apy() public {
        assertEq(reader.getVaultAPY(), 0);
    }

    function test_get_vault_fee() public {
        mockHub.setFeeBasisPoints(50);
        assertEq(reader.getVaultFee(), 50);
    }

    function test_get_last_harvest_time() public {
        // Use a very large timestamp to avoid any underflow issues
        uint256 timestamp = 1000000000000; // 1e12 seconds (~31,688 years)
        mockHub.setLastHarvest(timestamp);
        assertEq(reader.getLastHarvestTime(), timestamp);
    }

    function test_get_total_fees_collected() public {
        mockHub.setTotalFees(100 ether);
        assertEq(reader.getTotalFeesCollected(), 100 ether);
    }

    function test_emits_events() public {
        MockVault newVault = new MockVault();
        vm.expectEmit(true, true, false, true);
        emit VaultAddressUpdated(address(newVault));
        reader.setVaultAddress(address(newVault));

        MockComposer newComposer = new MockComposer();
        vm.expectEmit(true, true, false, true);
        emit ComposerAddressUpdated(address(newComposer));
        reader.setComposerAddress(address(newComposer));

        MockHub newHub = new MockHub();
        vm.expectEmit(true, true, false, true);
        emit HubAddressUpdated(address(newHub));
        reader.setHubAddress(address(newHub));
    }

    event VaultAddressUpdated(address newVault);
    event ComposerAddressUpdated(address newComposer);
    event HubAddressUpdated(address newHub);
}
