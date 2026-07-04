// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title Investing Token
 * @notice ERC20 token for the Investing project on Robinhood Chain.
 * @dev Fixed supply of 10,000 tokens.
 */
contract InvestingToken is ERC20 {
    uint256 public constant MAX_SUPPLY = 10_000 * 10 ** decimals();

    constructor() ERC20("Investing", "INVEST") {
        _mint(msg.sender, MAX_SUPPLY);
    }

    // Prevent minting/burning beyond the initial supply.
    function _mint(address account, uint256 amount) internal override {
        require(totalSupply() + amount <= MAX_SUPPLY, "Exceeds max supply");
        super._mint(account, amount);
    }

    function _burn(address account, uint256 amount) internal override {
        require(balanceOf(account) >= amount, "Burn amount exceeds balance");
        super._burn(account, amount);
    }
}