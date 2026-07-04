// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title InvestingConfig
 * @notice Shared protocol constants for the Investing project.
 */
library InvestingConfig {
    /// @dev Total fixed supply: 1 billion $INVEST
    uint256 internal constant MAX_SUPPLY = 1_000_000_000 ether;

    /// @dev Whole tokens of cumulative buy volume required per feather level
    uint256 internal constant TOKENS_PER_LEVEL = 1 ether;
}
