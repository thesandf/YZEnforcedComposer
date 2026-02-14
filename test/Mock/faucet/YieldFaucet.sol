// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
/// @notice A simple faucet that allows users to buy YZA with native tokens and sell YZA back for native tokens.
/// @dev This is a simplified example for testing purposes and should not be used in production as-is.
contract YieldFaucet is Ownable, ReentrancyGuard {
    IERC20 public immutable yza;
    /// @notice how many YZA per 1 native token (wei based)
    uint256 public constant MULTIPLIER = 10;
    event YieldBought(address indexed user, uint256 nativeIn, uint256 yzaOut);
    event YieldSold(address indexed user, uint256 yzaIn, uint256 nativeOut);
    constructor(address _yza, address _owner) Ownable(_owner) {
        yza = IERC20(_yza);
    }
    receive() external payable {
        _buyYield();
    }
    function buyYield() external payable nonReentrant {
        _buyYield();
    }
    function _buyYield() internal nonReentrant {
        require(msg.value > 0, "Zero value");
        uint256 reward = msg.value * MULTIPLIER;
        require(yza.balanceOf(address(this)) >= reward, "Faucet empty");
        bool sent = yza.transfer(msg.sender, reward);
        require(sent, "YZA transfer failed");
        emit YieldBought(msg.sender, msg.value, reward);
    }
    /// @notice Send YZA → receive native token back
    function sellYield(uint256 yzaAmount) external nonReentrant {
        require(yzaAmount > 0, "Zero");
        require(yzaAmount % MULTIPLIER == 0, "Invalid lot");
        bool pulled = yza.transferFrom(msg.sender, address(this), yzaAmount);
        require(pulled, "Pull failed");
        uint256 nativeOut = yzaAmount / MULTIPLIER;
        require(address(this).balance >= nativeOut, "No native");
        (bool ok,) = payable(msg.sender).call{value: nativeOut}("");
        require(ok, "ETH send failed");
        emit YieldSold(msg.sender, yzaAmount, nativeOut);
    }
    function withdrawNative(address to) external onlyOwner {
        (bool success,) = payable(to).call{value: address(this).balance}("");
        require(success, "ETH transfer failed");
    }
    function withdrawYZA(address to, uint256 amount) external onlyOwner {
        yza.transfer(to, amount);
    }
    function refillYZA(uint256 amount) external onlyOwner {
        bool ok = yza.transferFrom(msg.sender, address(this), amount);
        require(ok, "Refill failed");
    }
}
