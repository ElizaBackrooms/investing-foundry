// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title Investing Hook
 * @notice Uniswap v4 hook for the Investing project on Robinhood Chain.
 * @dev Emits events on swaps and allows the hook to call the NFT contract to mint based on user balance.
 */
contract InvestingHook {
    using Address for address;

    // Events
    event SwapOccurred(address indexed user, int256 amount0, int256 amount1);
    event MintTriggered(address indexed user, uint256 level);

    // Immutable addresses set at construction
    address public immutable investingToken; // InvestingToken contract
    address public immutable investingNFT;   // InvestingNFT contract

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
     * @param deltaBalances0 Change in token0 balance in the pool (positive if pool received token0)
     * @param deltaBalances1 Change in token1 balance in the pool
     * @param tickCumulative Cumulative tick value
     * @param feeGrowth0X128 Fee growth in token0
     * @param feeGrowth1X128 Fee growth in token1
     * @param liquidity Current liquidity in the pool
     * @param sqrtPriceX96 Current sqrt price
     * @param tick Current tick
     * @param hookData Arbitrary data passed by the swap initiator (we expect the user address)
     */
    function afterSwap(
        int256 deltaBalances0,
        int256 deltaBalances1,
        uint256 /* tickCumulative */,
        uint128 /* feeGrowth0X128 */,
        uint128 /* feeGrowth1X128 */,
        uint256 /* liquidity */,
        uint256 /* sqrtPriceX96 */,
        int24 /* tick */,
        bytes calldata hookData
    ) external {
        // Emit swap event for indexing
        emit SwapOccurred(msg.sender, deltaBalances0, deltaBalances1);

        // We expect hookData to be the user address (20 bytes)
        if (hookData.length != 20) {
            // If no hookData, we cannot determine the user, so skip minting
            return;
        }
        address user = address(uint160(uint256(abi.decode(hookData, (address)))));

        // Get the user's current balance of InvestingToken
        // We assume the token is ERC20 with 18 decimals
        uint256 balance = IInvestingToken(investingToken).balanceOf(user);
        // Compute level = balance / 1e18 (whole number)
        uint256 level = balance / 1e18;

        // Emit mint triggered event
        emit MintTriggered(user, level);

        // Call the NFT contract to mint up to the user's level
        // The NFT contract will only mint if the level is greater than what the user has already claimed
        IInvestingNFT(investingNFT).mintUpTo(user, level);
    }

    // --- Other hook interfaces (empty implementations to save gas) ---

    function initialize(address /* pool */) external {}
    function beforeAddLiquidity(
        uint256 /* amount0Desired */,
        uint256 /* amount1Desired */,
        uint256 /* amount0Min */,
        uint256 /* amount1Min */,
        bytes calldata /* hookData */
    ) external returns (uint256 amount0, uint256 amount1) {
        amount0 = 0;
        amount1 = 0;
    }
    function afterAddLiquidity(
        uint256 /* amount0 */,
        uint256 /* amount1 */,
        uint256 /* liquidity */,
        int256 /* fee */,
        bytes calldata /* hookData */
    ) external {}
    function beforeRemoveLiquidity(
        uint256 /* amount0 */,
        uint256 /* amount1 */,
        uint256 /* amount0Min */,
        uint256 /* amount1Min */,
        bytes calldata /* hookData */
    ) external returns (uint256 amount0, uint256 amount1) {
        amount0 = 0;
        amount1 = 0;
    }
    function afterRemoveLiquidity(
        uint256 /* amount0 */,
        uint256 /* amount1 */,
        uint256 /* liquidity */,
        int256 /* fee */,
        bytes calldata /* hookData */,
        bool /* refund */ 
    ) external {}
    function beforeSwap(
        int256 /* amountSpecified */,
        uint160 /* sqrtPriceLimitX96 */,
        bytes calldata /* hookData */,
        int256 /* amount0 */,
        int256 /* amount1 */
    ) external returns (int256 amount0Delta, int256 amount1Delta) {
        amount0Delta = 0;
        amount1Delta = 0;
    }
    function beforeInitialize(
        uint160 /* initialSqrtPriceX96 */,
        uint256 /* initialLiquidity */
    ) external {}
}

// Interface for InvestingToken (minimal for balanceOf)
interface IInvestingToken {
    function balanceOf(address account) external view returns (uint256);
}

// Interface for InvestingNFT (minimal for mintUpTo)
interface IInvestingNFT {
    function mintUpTo(address user, uint256 level) external;
}