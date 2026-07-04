// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IInvestingNFT} from "./interfaces/IInvestingNFT.sol";

/**
 * @title Investing Hook
 * @notice Uniswap v4 hook that records INVEST purchased on swaps.
 * @dev Eligibility is cumulative buy volume, not wallet balance at claim time.
 */
contract InvestingHook {
    event SwapOccurred(address indexed user, int256 amount0, int256 amount1);
    event InvestRecorded(address indexed user, uint256 amount, uint256 eligibleLevel);

    address public immutable investingNFT;
    bool public immutable investIsToken0;

    constructor(address _investingNFT, bool _investIsToken0) {
        require(_investingNFT != address(0), "NFT zero");
        investingNFT = _investingNFT;
        investIsToken0 = _investIsToken0;
    }

    function afterSwap(
        int256 deltaBalances0,
        int256 deltaBalances1,
        uint256,
        uint128,
        uint128,
        uint256,
        uint256,
        int24,
        bytes calldata hookData
    ) external {
        address user = _decodeUser(hookData);
        if (user == address(0)) {
            return;
        }

        emit SwapOccurred(user, deltaBalances0, deltaBalances1);

        uint256 investBought = _investBought(deltaBalances0, deltaBalances1);
        if (investBought == 0) {
            return;
        }

        IInvestingNFT(investingNFT).recordInvestFromSwap(user, investBought);

        uint256 accumulated = IInvestingNFT(investingNFT).investAccumulated(user);
        uint256 tokensPerLevel = IInvestingNFT(investingNFT).TOKENS_PER_LEVEL();
        uint256 eligible = accumulated / tokensPerLevel;
        emit InvestRecorded(user, investBought, eligible);
    }

    function _investBought(int256 deltaBalances0, int256 deltaBalances1) internal view returns (uint256) {
        if (investIsToken0) {
            if (deltaBalances0 >= 0) {
                return 0;
            }
            return uint256(-deltaBalances0);
        }
        if (deltaBalances1 >= 0) {
            return 0;
        }
        return uint256(-deltaBalances1);
    }

    function _decodeUser(bytes calldata hookData) internal pure returns (address user) {
        if (hookData.length == 20) {
            return address(bytes20(hookData));
        }
        if (hookData.length >= 32) {
            return abi.decode(hookData, (address));
        }
        return address(0);
    }

    function initialize(address) external {}
    function beforeAddLiquidity(uint256, uint256, uint256, uint256, bytes calldata)
        external
        pure
        returns (uint256 amount0, uint256 amount1)
    {
        amount0 = 0;
        amount1 = 0;
    }
    function afterAddLiquidity(uint256, uint256, uint256, int256, bytes calldata) external {}
    function beforeRemoveLiquidity(uint256, uint256, uint256, uint256, bytes calldata)
        external
        pure
        returns (uint256 amount0, uint256 amount1)
    {
        amount0 = 0;
        amount1 = 0;
    }
    function afterRemoveLiquidity(uint256, uint256, uint256, int256, bytes calldata, bool) external {}
    function beforeSwap(int256, uint160, bytes calldata, int256, int256)
        external
        pure
        returns (int256 amount0Delta, int256 amount1Delta)
    {
        amount0Delta = 0;
        amount1Delta = 0;
    }
    function beforeInitialize(uint160, uint256) external {}
}
