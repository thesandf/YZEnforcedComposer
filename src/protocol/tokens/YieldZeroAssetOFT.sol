// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OFT} from "@layerzerolabs/oft-evm/contracts/OFT.sol";

contract YieldZeroAssetOFT is OFT {
    uint256 public constant MAX_SUPPLY = 1_000_000_000 ether;

    bool public immutable IS_HUB;

    /**
     * @notice Constructs the Assert OFT contract
     */
    constructor(string memory _name, string memory _symbol, address _lzEndpoint, address _delegate, bool _isHub)
        OFT(_name, _symbol, _lzEndpoint, _delegate)
        Ownable(_delegate)
    {
        IS_HUB = _isHub;
        if (IS_HUB) {
            _mint(_delegate, MAX_SUPPLY);
        }
    }
}
