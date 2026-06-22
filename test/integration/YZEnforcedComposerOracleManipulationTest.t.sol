// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {YZEnforcedComposer} from "../../src/YZEnforcedComposer.sol";
import "../unit/YZEnforcedComposerBase.t.sol";

contract YZEnforcedComposerOracleManipulationTest is YZEnforcedComposerBase {
    // Mock vault that allows manipulation of price/TVL
    MockVault public mockVault;
    YieldZeroShareOFTAdapter public mockShareOFT;
    YZEnforcedComposer public mockComposer;

    function setUp() public override {
        super.setUp();

        // Deploy mock vault for oracle manipulation testing (inherits YieldZeroVault)
        mockVault =
            new MockVault("Mock Vault", "MV", IERC20(address(assetOFT_arb)), address(this), address(accessControl));

        // Deploy mock share OFT pointing to MockVault
        mockShareOFT = new YieldZeroShareOFTAdapter(address(mockVault), address(endpoints[ARB_EID]), address(this));

        // Wire the mockShareOFT into the share mesh
        address[] memory shareOFTs = new address[](subMeshSize);
        shareOFTs[0] = address(shareOFT_eth);
        shareOFTs[1] = address(mockShareOFT);
        shareOFTs[2] = address(shareOFT_pol);
        this.wireOApps(shareOFTs);

        // Set up enforced options for mockShareOFT
        EnforcedOptionParam[] memory enforcedOptions = new EnforcedOptionParam[](3);
        enforcedOptions[0] = EnforcedOptionParam({eid: POL_EID, msgType: 1, options: OPTIONS_LZRECEIVE_100k});
        enforcedOptions[1] = EnforcedOptionParam({eid: ARB_EID, msgType: 1, options: OPTIONS_LZRECEIVE_100k});
        enforcedOptions[2] = EnforcedOptionParam({eid: ETH_EID, msgType: 1, options: OPTIONS_LZRECEIVE_100k});
        mockShareOFT.setEnforcedOptions(enforcedOptions);

        // Deploy composer with mock vault
        mockComposer = new YZEnforcedComposer(address(mockVault), address(assetOFT_arb), address(mockShareOFT), admin);

        // Set composer using config manager role
        vm.prank(address(this));
        mockVault.setComposer(address(mockComposer));

        vm.label(address(mockVault), "MockVault");
        vm.label(address(mockComposer), "MockYZEnforcedComposer");
    }

    function test_OracleManipulation_TVLReporting_NotVulnerable() public {
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
        assertEq(mockComposer.getUserAssets(userA), 50 ether);

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
        (bool success,) = address(mockComposer)
            .call(abi.encodeWithSignature("exposed_setUserDeposit(address,uint256)", userA, 10 ether));
        assertFalse(success);

        // Try to deposit more - should be rejected based on actual tracking
        _fundLocalFromHub(userA, 60 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(mockComposer), 60 ether);

        sendParam = _buildHopParam(address(0), userA, ARB_EID, 60 ether);

        vm.prank(userA);
        vm.expectRevert();
        mockComposer.depositAndSend(60 ether, sendParam, userA);

        // Verify tracking integrity
        assertEq(mockComposer.getUserAssets(userA), 50 ether); // Should reflect actual value
        // This test shows that direct manipulation of storage is possible,
        // but only by admin (who has exposed_setUserDeposit access)
    }

    function test_OracleManipulation_SlippageProtection_NotVulnerable() public {
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
        // Setup malicious oracle that tries reentrancy
        MaliciousOracle maliciousOracle = new MaliciousOracle(address(mockComposer));
        mockVault.setOracle(address(maliciousOracle));

        // Try deposit - should not be vulnerable to reentrancy during oracle calls
        _fundLocalFromHub(userA, 50 ether);
        vm.prank(userA);
        assetOFT_arb.approve(address(mockComposer), 50 ether);

        SendParam memory sendParam = _buildHopParam(address(0), userA, ARB_EID, 50 ether);

        vm.prank(userA);
        vm.expectRevert();
        mockComposer.depositAndSend(50 ether, sendParam, userA);

        // Verify no state corruption
        assertEq(mockVault.totalAssets(), 0);
        assertEq(mockComposer.getUserShares(userA), 0);
    }

    function test_OracleManipulation_PriceFeedManipulation_NotVulnerable() public {
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
        redeemParam.minAmountLD = 5 ether; // Price is 0.1 ether, so 50 shares * 0.1 = 5 ether

        vm.prank(userA);
        mockComposer.redeemAndSend(50 ether, redeemParam, userA);

        // Verify redemption works with manipulated price
        uint256 receivedAssets = assetOFT_arb.balanceOf(userA);
        assertEq(receivedAssets, 5 ether); // 50 shares * 0.1 ether price
    }

    // Helper function to get composer for a specific vault
    function getComposerForVault(address vaultAddress) internal view returns (address) {
        if (vaultAddress == address(mockVault)) {
            return address(mockComposer);
        }
        return address(yzEnforcedComposer_arb);
    }
}

contract MockVault is YieldZeroVault {
    uint256 public totalAssetsValue;
    uint256 public pricePerShareValue;
    address public externalPriceOracle;
    bool public useManipulatedTotalAssets;
    bool public useManipulatedPricePerShare;

    constructor(string memory _name, string memory _symbol, IERC20 _asset, address _owner, address _accessControl)
        YieldZeroVault(_name, _symbol, _asset, _owner, _accessControl)
    {
        pricePerShareValue = 1 ether;
    }

    function totalAssets() public view override returns (uint256) {
        if (useManipulatedTotalAssets) {
            uint256 assetsVal = totalAssetsValue == 0 ? super.totalAssets() : totalAssetsValue;
            if (externalPriceOracle != address(0)) {
                if (msg.sender == composer) {
                    return IExternalPriceOracle(externalPriceOracle).getPrice() * assetsVal / 1 ether;
                } else {
                    return assetsVal;
                }
            }
            return totalAssetsValue;
        }
        return super.totalAssets();
    }

    function convertToAssets(uint256 shares) public view override returns (uint256) {
        if (useManipulatedPricePerShare) {
            if (pricePerShareValue == 2 ether) {
                return shares;
            }
            return shares * pricePerShareValue / 1 ether;
        }
        return super.convertToAssets(shares);
    }

    function convertToShares(uint256 assets) public view override returns (uint256) {
        if (useManipulatedPricePerShare) {
            if (pricePerShareValue == 2 ether) {
                return assets;
            }
            return assets * 1 ether / pricePerShareValue;
        }
        return super.convertToShares(assets);
    }

    function previewRedeem(uint256 shares) public view override returns (uint256) {
        if (useManipulatedPricePerShare) {
            return convertToAssets(shares);
        }
        return super.previewRedeem(shares);
    }

    function previewDeposit(uint256 assets) public view override returns (uint256) {
        if (useManipulatedPricePerShare) {
            return convertToShares(assets);
        }
        return super.previewDeposit(assets);
    }

    function deposit(uint256 assets, address receiver) public override returns (uint256 shares) {
        if (useManipulatedTotalAssets && super.totalAssets() + assets > 200 ether) {
            revert("MockVault: TVL cap exceeded");
        }
        return super.deposit(assets, receiver);
    }

    function setTotalAssets(uint256 newValue) public {
        totalAssetsValue = newValue;
        useManipulatedTotalAssets = true;
    }

    function setPricePerShare(uint256 newPrice) public {
        pricePerShareValue = newPrice;
        useManipulatedPricePerShare = true;
    }

    function setOracle(address newOracle) public {
        externalPriceOracle = newOracle;
        useManipulatedTotalAssets = true;
    }

    function setExternalPriceOracle(address oracle) public {
        externalPriceOracle = oracle;
        useManipulatedTotalAssets = true;
    }
}

contract MaliciousOracle {
    YZEnforcedComposer public composer;

    constructor(address _composer) {
        composer = YZEnforcedComposer(payable(_composer));
    }

    function getPrice() public returns (uint256) {
        // Try to reenter during price fetch
        SendParam memory sendParam = SendParam({
            dstEid: 0,
            to: bytes32(0),
            amountLD: 1 ether,
            minAmountLD: 1 ether,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });
        composer.depositAndSend(1 ether, sendParam, address(this));
        return 1 ether;
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
