// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OFT} from "@layerzerolabs/oft-evm/contracts/OFT.sol";
contract YieldZeroShareOFT is OFT {
    /// @notice Constructs the Share OFT contract
/// @dev dont mint share tokens directly as this breaks the vault's share-to-asset ratio
    constructor(string memory _name, string memory _symbol, address _lzEndpoint, address _delegate)
        OFT(_name, _symbol, _lzEndpoint, _delegate)
        Ownable(_delegate)
    {}
}
