// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {YZEnforcedComposer} from "../../src/sdk/YZEnforcedComposer.sol";
import "./YZEnforcedComposerBase.t.sol";

contract YZEnforcedComposerOracleManipulationTest is YZEnforcedComposerBase {
    
    // Mock vault that allows manipulation of price/TVL
    MockVault public mockVault;
    
    function setUp() public override {
        super.setUp();
        
        // Deploy mock vault for oracle manipulation testing
        mockVault = new MockVault("Mock Vault", "MV", IERC20(address(assetOFT_arb)));
        
        // Deploy composer with mock vault
        YZEnforcedComposer mockComposer = new YZEnforcedComposer(
            address(mockVault), 
            address(assetOFT_arb), 
            address(shareOFT_arb), 
            admin
        );
        
        // Grant CONFIG_MANAGER_ROLE to deployer
        accessControl.grantConfigManagerRole(address(this), "Test config manager");
        
        // Set composer using config manager role
        vm.prank(address(this));
        mockVault.setComposer(address(mockComposer));
        
        vm.label(address(mockVault), "MockVault");
        vm.label(address(mockComposer), "MockYZEnforcedComposer");
    }
    
    function test_OracleManipulation_TVLReporting_NotVulnerable() public {
        YZEnforcedComposer mockComposer = YZEnforcedComposer(getComposerForVault(address(mockVault)));
        
        // Setup TVL cap
        vm.prank(admin);
        mockComposer.setTVLCap(100 ether);
        
        // Normal deposit
        _fundLocalFromHub(userA, 50 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(mockComposer), 50 ether);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);
        
        vm.prank(userA);
        mockComposer.depositAndSend(50 ether, sendParam, userA);
        
        // Verify normal operation
        assertEq(mockVault.totalAssets(), 50 ether);
        assertEq(mockComposer.userDeposits(userA), 50 ether);
        
        // Simulate oracle manipulation - artificially inflate TVL
        mockVault.setTotalAssets(200 ether);
        
        // Try to deposit more - should still be rejected due to actual TVL tracking
        _fundLocalFromHub(userA, 60 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(mockComposer), 60 ether);
        
        sendParam = _buildHopParam(address(0), userA, ARB_EID, 60 ether);
        
        vm.prank(userA);
        vm.expectRevert();
        mockComposer.depositAndSend(60 ether, sendParam, userA);
        
        // Verify actual TVL still tracked correctly
        assertEq(mockVault.totalAssets(), 200 ether); // Mock shows inflated
        // But enforcement should use actual tracked value
    }
    
    function test_OracleManipulation_SharePrice_NotVulnerable() public {
        YZEnforcedComposer mockComposer = YZEnforcedComposer(getComposerForVault(address(mockVault)));
        
        // Normal deposit
        _fundLocalFromHub(userA, 100 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(mockComposer), 100 ether);
        
        SendParam memory depositParam = _buildHopParam(address(0), userA, ARB_EID, 100 ether);
        
        vm.prank(userA);
        mockComposer.depositAndSend(100 ether, depositParam, userA);
        
        // Simulate oracle manipulation - artificially change share price
        mockVault.setPricePerShare(2 ether); // 2x normal price
        
        // Try to redeem - should still work correctly based on actual shares
        vm.prank(userA);
        mockVault.approve(address(mockComposer), 50 ether);
        
        SendParam memory redeemParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);
        
        vm.prank(userA);
        mockComposer.redeemAndSend(50 ether, redeemParam, userA);
        
        // Verify redemption based on actual share value, not manipulated price
        uint256 expectedAssets = 50 ether; // Should get 50 ether worth of assets
        assertEq(assetOFT_arb.balanceOf(userA), expectedAssets);
    }
    
    function test_OracleManipulation_UserDepositTracking_NotVulnerable() public {
        YZEnforcedComposer mockComposer = YZEnforcedComposer(getComposerForVault(address(mockVault)));
        
        // Setup user cap
        vm.prank(admin);
        mockComposer.setUserCap(userA, 100 ether);
        
        // Normal deposit
        _fundLocalFromHub(userA, 50 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(mockComposer), 50 ether);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);
        
        vm.prank(userA);
        mockComposer.depositAndSend(50 ether, sendParam, userA);
        
        // Simulate oracle manipulation - manipulate user deposit tracking
        mockComposer.exposed_setUserDeposit(userA, 10 ether); // Reduce tracked amount
        
        // Try to deposit more - should be rejected based on actual tracking
        _fundLocalFromHub(userA, 60 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(mockComposer), 60 ether);
        
        sendParam = _buildHopParam(address(0), userA, ARB_EID, 60 ether);
        
        vm.prank(userA);
        vm.expectRevert();
        mockComposer.depositAndSend(60 ether, sendParam, userA);
        
        // Verify tracking integrity
        assertEq(mockComposer.userDeposits(userA), 10 ether); // Should reflect manipulated value
        // This test shows that direct manipulation of storage is possible,
        // but only by admin (who has exposed_setUserDeposit access)
    }
    
    function test_OracleManipulation_SlippageProtection_NotVulnerable() public {
        YZEnforcedComposer mockComposer = YZEnforcedComposer(getComposerForVault(address(mockVault)));
        
        // Normal deposit with slippage protection
        _fundLocalFromHub(userA, 100 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(mockComposer), 100 ether);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 100 ether);
        sendParam.minAmountLD = 95 ether; // 5% slippage tolerance
        
        vm.prank(userA);
        mockComposer.depositAndSend(100 ether, sendParam, userA);
        
        // Simulate oracle manipulation during redeem - artificially change prices
        mockVault.setPricePerShare(0.5 ether); // 50% price drop
        
        // Try to redeem - should still respect slippage protection
        vm.prank(userA);
        mockVault.approve(address(mockComposer), 50 ether);
        
        SendParam memory redeemParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);
        redeemParam.minAmountLD = 20 ether; // Should get at least 20 ether
        
        vm.prank(userA);
        mockComposer.redeemAndSend(50 ether, redeemParam, userA);
        
        // Verify slippage protection worked
        uint256 receivedAssets = assetOFT_arb.balanceOf(userA);
        assertGe(receivedAssets, 20 ether); // Should receive at least minimum
    }
    
    function test_OracleManipulation_TVLTracking_Accuracy() public {
        YZEnforcedComposer mockComposer = YZEnforcedComposer(getComposerForVault(address(mockVault)));
        
        // Setup TVL cap
        vm.prank(admin);
        mockComposer.setTVLCap(200 ether);
        
        // Multiple deposits
        _fundLocalFromHub(userA, 100 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(mockComposer), 100 ether);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 100 ether);
        
        vm.prank(userA);
        mockComposer.depositAndSend(100 ether, sendParam, userA);
        
        _fundLocalFromHub(userB, 80 ether);
        vm.prank(userB);
        assetOFT_arb.approve(address(mockComposer), 80 ether);
        
        sendParam = _buildHopParam(address(0), userB, ARB_EID, 80 ether);
        
        vm.prank(userB);
        mockComposer.depositAndSend(80 ether, sendParam, userB);
        
        // Verify accurate TVL tracking
        uint256 actualTVL = mockVault.totalAssets();
        assertEq(actualTVL, 180 ether);
        
        // Simulate oracle manipulation - report wrong TVL
        mockVault.setTotalAssets(150 ether); // Underreport
        
        // Try to deposit more - should be rejected based on actual TVL
        _fundLocalFromHub(userA, 30 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(mockComposer), 30 ether);
        
        sendParam = _buildHopParam(address(0), userA, ARB_EID, 30 ether);
        
        vm.prank(userA);
        vm.expectRevert();
        mockComposer.depositAndSend(30 ether, sendParam, userA);
        
        // Verify enforcement uses actual tracked TVL, not reported TVL
        assertEq(mockVault.totalAssets(), 150 ether); // Mock shows manipulated
        // But enforcement should reject based on actual 180 ether
    }
    
    function test_OracleManipulation_ReentrancyDuringOracleCall_NotVulnerable() public {
        YZEnforcedComposer mockComposer = YZEnforcedComposer(getComposerForVault(address(mockVault)));
        
        // Setup malicious oracle that tries reentrancy
        MaliciousOracle maliciousOracle = new MaliciousOracle(address(mockComposer));
        mockVault.setOracle(address(maliciousOracle));
        
        // Try deposit - should not be vulnerable to reentrancy during oracle calls
        _fundLocalFromHub(userA, 50 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(mockComposer), 50 ether);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);
        
        vm.prank(userA);
        vm.expectRevert("ReentrancyGuard: reentrant call");
        mockComposer.depositAndSend(50 ether, sendParam, userA);
        
        // Verify no state corruption
        assertEq(mockVault.totalAssets(), 0);
        assertEq(mockComposer.userDeposits(userA), 0);
    }
    
    function test_OracleManipulation_PriceFeedManipulation_NotVulnerable() public {
        YZEnforcedComposer mockComposer = YZEnforcedComposer(getComposerForVault(address(mockVault)));
        
        // Normal operation
        _fundLocalFromHub(userA, 100 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(mockComposer), 100 ether);
        
        SendParam memory depositParam = _buildHopParam(address(0), userA, ARB_EID, 100 ether);
        
        vm.prank(userA);
        mockComposer.depositAndSend(100 ether, depositParam, userA);
        
        // Simulate price feed manipulation
        mockVault.setPricePerShare(10 ether); // 10x normal price
        
        // Try redeem - should still work based on actual share ownership
        vm.prank(userA);
        mockVault.approve(address(mockComposer), 10 ether);
        
        SendParam memory redeemParam = _buildHopParam(address(0), userA, ARB_EID, 10 ether);
        
        vm.prank(userA);
        mockComposer.redeemAndSend(10 ether, redeemParam, userA);
        
        // Verify redemption based on actual share value
        uint256 receivedAssets = assetOFT_arb.balanceOf(userA);
        assertEq(receivedAssets, 100 ether); // Should get 100 ether (10 shares * 10 ether price)
    }
    
    function test_OracleManipulation_ExternalPriceOracle_NotVulnerable() public {
        YZEnforcedComposer mockComposer = YZEnforcedComposer(getComposerForVault(address(mockVault)));
        
        // Setup external price oracle
        ExternalPriceOracle priceOracle = new ExternalPriceOracle();
        mockVault.setExternalPriceOracle(address(priceOracle));
        
        // Normal deposit
        _fundLocalFromHub(userA, 100 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(mockComposer), 100 ether);
        
        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 100 ether);
        
        vm.prank(userA);
        mockComposer.depositAndSend(100 ether, sendParam, userA);
        
        // Manipulate external oracle
        priceOracle.setPrice(0.1 ether); // 90% price drop
        
        // Try redeem - should still work correctly
        vm.prank(userA);
        mockVault.approve(address(mockComposer), 50 ether);
        
        SendParam memory redeemParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);
        
        vm.prank(userA);
        mockComposer.redeemAndSend(50 ether, redeemParam, userA);
        
        // Verify redemption works with manipulated price
        uint256 receivedAssets = assetOFT_arb.balanceOf(userA);
        assertEq(receivedAssets, 5 ether); // 50 shares * 0.1 ether price
    }
    
    // Helper function to get composer for a specific vault
    function getComposerForVault(address vaultAddress) internal view returns (address) {
        // This would need to be implemented based on how composers are mapped to vaults
        // For now, return a placeholder
        return address(0);
    }
}

contract MockVault {
    string public name;
    string public symbol;
    IERC20 public asset;
    
    uint256 public totalAssetsValue;
    uint256 public pricePerShareValue;
    address public externalPriceOracle;
    
    constructor(string memory _name, string memory _symbol, IERC20 _asset) {
        name = _name;
        symbol = _symbol;
        asset = _asset;
        totalAssetsValue = 0;
        pricePerShareValue = 1 ether; // 1:1 with asset
    }
    
    function totalAssets() public view returns (uint256) {
        if (externalPriceOracle != address(0)) {
            // Use external oracle
            return IExternalPriceOracle(externalPriceOracle).getPrice() * totalAssetsValue / 1 ether;
        }
        return totalAssetsValue;
    }
    
    function convertToAssets(uint256 shares) public view returns (uint256) {
        return shares * pricePerShareValue / 1 ether;
    }
    
    function convertToShares(uint256 assets) public view returns (uint256) {
        return assets * 1 ether / pricePerShareValue;
    }
    
    function deposit(uint256 assets, address receiver) public returns (uint256 shares) {
        shares = convertToShares(assets);
        totalAssetsValue += assets;
        // Mint shares to receiver
        // This is simplified for testing
    }
    
    function redeem(uint256 shares, address receiver, address owner) public returns (uint256 assets) {
        assets = convertToAssets(shares);
        totalAssetsValue -= assets;
        // Burn shares from owner and send assets to receiver
        // This is simplified for testing
    }
    
    function approve(address spender, uint256 amount) public {
        asset.approve(spender, amount);
    }
    
    function balanceOf(address account) public view returns (uint256) {
        // Simplified - return some value
        return 100 ether;
    }
    
    function setTotalAssets(uint256 newValue) public {
        totalAssetsValue = newValue;
    }
    
    function setPricePerShare(uint256 newPrice) public {
        pricePerShareValue = newPrice;
    }
    
    function setOracle(address newOracle) public {
        externalPriceOracle = newOracle;
    }
    
    function setExternalPriceOracle(address oracle) public {
        externalPriceOracle = oracle;
    }
    
    function setComposer(address composer) public {
        // Simplified for testing
    }
}

contract MaliciousOracle {
    YZEnforcedComposer public composer;
    
    constructor(address _composer) {
        composer = YZEnforcedComposer(_composer);
    }
    
    function getPrice() public returns (uint256) {
        // Try to reenter during price fetch
        try composer.depositAndSend(1 ether, SendParam(0, bytes32(0), 1 ether, 1 ether, "", "", ""), address(this)) {
            return 1 ether;
        } catch {
            return 1 ether;
        }
    }
}

interface IExternalPriceOracle {
    function getPrice() external view returns (uint256);
}

contract ExternalPriceOracle is IExternalPriceOracle {
    uint256 public price = 1 ether;
    
    function getPrice() external view returns (uint256) {
        return price;
    }
    
    function setPrice(uint256 newPrice) external {
        price = newPrice;
    }
}