// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IInvestingToken} from "./interfaces/IInvestingToken.sol";

/**
 * @title Investing Hook
 * @notice Uniswap v4 hook for the Investing project on Robinhood Chain.
 * @dev Emits events on swaps. NFT claiming is user-initiated via claimNextFeather().
 */
contract InvestingHook {
    // Events
    event SwapOccurred(address indexed user, int256 amount0, int256 amount1);
    event MintTriggered(address indexed user, uint256 level);

    // Immutable addresses set at construction
    address public immutable investingToken; // InvestingToken contract
    address public immutable investingNFT; // InvestingNFT contract

    /**
     * @dev Constructor sets the token and NFT addresses
     * @param _investingToken Address of the InvestingToken contract
     * @param _investingNFT   Address of the InvestingNFT contract
     */
    constructor(address _investingToken, address _investingNFT) {
        require(_investingToken != address(0), "Token zero");
        require(_investingNFT != address(0), "NFT zero");
        investingToken = _investingToken;
        investingNFT = _investingNFT;
    }

    /**
     * @dev Called by the PoolManager after a swap
     * @param hookData Arbitrary data passed by the swap initiator (we expect the user address)
     */
    function afterSwap(
        int256 deltaBalances0,
        int256 deltaBalances1,
        uint256, /* tickCumulative */
        uint128, /* feeGrowth0X128 */
        uint128, /* feeGrowth1X128 */
        uint256, /* liquidity */
        uint256, /* sqrtPriceX96 */
        int24, /* tick */
        bytes calldata hookData
    ) external {
        // Emit swap event for indexing
        emit SwapOccurred(msg.sender, deltaBalances0, deltaBalances1);

        address user;
        if (hookData.length == 20) {
            user = address(bytes20(hookData));
        } else if (hookData.length >= 32) {
            user = abi.decode(hookData, (address));
        } else {
            return;
        }

        uint256 balance = IInvestingToken(investingToken).balanceOf(user);
        uint256 level = balance / 1e18;

        emit MintTriggered(user, level);
    }

    // --- Other hook interfaces (empty implementations to save gas) ---

    function initialize(address) external {}
    function beforeAddLiquidity(
        uint256, /* amount0Desired */
        uint256, /* amount1Desired */
        uint256, /* amount0Min */
        uint256, /* amount1Min */
        bytes calldata /* hookData */
    ) external returns (uint256 amount0, uint256 amount1) {
        amount0 = 0;
        amount1 = 0;
    }
    function afterAddLiquidity(
        uint256, /* amount0 */
        uint256, /* amount1 */
        uint256, /* liquidity */
        int256, /* fee */
        bytes calldata /* hookData */
    ) external {}
    function beforeRemoveLiquidity(
        uint256, /* amount0 */
        uint256, /* amount1 */
        uint256, /* amount0Min */
        uint256, /* amount1Min */
        bytes calldata /* hookData */
    ) external returns (uint256 amount0, uint256 amount1) {
        amount0 = 0;
        amount1 = 0;
    }
    function afterRemoveLiquidity(
        uint256, /* amount0 */
        uint256, /* amount1 */
        uint256, /* liquidity */
        int256, /* fee */
        bytes calldata, /* hookData */
        bool /* refund */
    ) external {}
    function beforeSwap(
        int256, /* amountSpecified */
        uint160, /* sqrtPriceLimitX96 */
        bytes calldata, /* hookData */
        int256, /* amount0 */
        int256 /* amount1 */
    ) external returns (int256 amount0Delta, int256 amount1Delta) {
        amount0Delta = 0;
        amount1Delta = 0;
    }
    function beforeInitialize(uint160, uint256) external {}
}
