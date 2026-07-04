// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {InvestingConfig} from "./InvestingConfig.sol";

/**
 * @title Investing Token
 * @notice ERC20 token for the Investing project on Robinhood Chain.
 * @dev Fixed supply of 1 billion tokens.
 */
contract InvestingToken is ERC20 {
    uint256 public constant MAX_SUPPLY = InvestingConfig.MAX_SUPPLY;

    constructor() ERC20("Investing", "INVEST") {
        _mint(msg.sender, MAX_SUPPLY);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from == address(0) && totalSupply() + value > MAX_SUPPLY) {
            revert("Exceeds max supply");
        }
        if (to == address(0)) {
            revert("Burn disabled");
        }
        super._update(from, to, value);
    }
}
