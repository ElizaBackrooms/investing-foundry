// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title InvestingConfig
 * @notice Shared protocol constants for the Investing project.
 */
library InvestingConfig {
    /// @dev Total fixed supply: 1 billion $INVEST
    uint256 internal constant MAX_SUPPLY = 1_000_000_000 ether;

    /// @dev Cumulative buy volume per feather level (100k tokens).
    ///      Level 1 at 100k, level 10 at 1M, level 100 at 10M on 1B supply.
    uint256 internal constant TOKENS_PER_LEVEL = 100_000 ether;

    /// @dev Minimum INVEST bought in a single swap before volume counts (anti-wash).
    uint256 internal constant MIN_SWAP_VOLUME = 1_000 ether;
}
