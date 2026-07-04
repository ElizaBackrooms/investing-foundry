// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BaseHookStub} from "./BaseHookStub.sol";
import {InvestingConfig} from "./InvestingConfig.sol";
import {IInvestingNFT} from "./interfaces/IInvestingNFT.sol";

/**
 * @title Investing Hook
 * @notice Uniswap v4 hook that records INVEST purchased on swaps in the canonical pool.
 * @dev Eligibility is cumulative buy volume, not wallet balance at claim time.
 */
contract InvestingHook is BaseHookStub {
    using Hooks for IHooks;

    event SwapOccurred(address indexed user, int128 delta0, int128 delta1);
    event InvestRecorded(address indexed user, uint256 amount, uint256 eligibleLevel);

    IPoolManager public immutable poolManager;
    address public immutable investingNFT;
    Currency public immutable investCurrency;
    Currency public immutable quoteCurrency;
    bool public immutable investIsToken0;

    error OnlyPoolManager();
    error PoolManagerZero();
    error NftZero();
    error InvestTokenZero();
    error QuoteTokenZero();
    error SameToken();

    modifier onlyPoolManager() {
        if (msg.sender != address(poolManager)) revert OnlyPoolManager();
        _;
    }

    constructor(IPoolManager _poolManager, address _investingNFT, address _investToken, address _quoteToken) {
        if (address(_poolManager) == address(0)) revert PoolManagerZero();
        if (_investingNFT == address(0)) revert NftZero();
        if (_investToken == address(0)) revert InvestTokenZero();
        if (_quoteToken == address(0)) revert QuoteTokenZero();
        if (_investToken == _quoteToken) revert SameToken();

        poolManager = _poolManager;
        investingNFT = _investingNFT;
        investCurrency = Currency.wrap(_investToken);
        quoteCurrency = Currency.wrap(_quoteToken);
        investIsToken0 = _investToken < _quoteToken;

        IHooks(address(this))
            .validateHookPermissions(
                Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: false,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            })
            );
    }

    function afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata,
        BalanceDelta delta,
        bytes calldata hookData
    ) external override onlyPoolManager returns (bytes4, int128) {
        if (!_isCanonicalPool(key)) {
            return (IHooks.afterSwap.selector, 0);
        }

        address user = _resolveUser(sender, hookData);
        if (user == address(0)) {
            return (IHooks.afterSwap.selector, 0);
        }

        emit SwapOccurred(user, delta.amount0(), delta.amount1());

        uint256 investBought = _investBought(delta);
        if (investBought < InvestingConfig.MIN_SWAP_VOLUME) {
            return (IHooks.afterSwap.selector, 0);
        }

        IInvestingNFT(investingNFT).recordInvestFromSwap(user, investBought);

        uint256 accumulated = IInvestingNFT(investingNFT).investAccumulated(user);
        uint256 tokensPerLevel = IInvestingNFT(investingNFT).TOKENS_PER_LEVEL();
        uint256 eligible = accumulated / tokensPerLevel;
        emit InvestRecorded(user, investBought, eligible);

        return (IHooks.afterSwap.selector, 0);
    }

    function _isCanonicalPool(PoolKey calldata key) internal view returns (bool) {
        return (key.currency0 == investCurrency && key.currency1 == quoteCurrency)
            || (key.currency0 == quoteCurrency && key.currency1 == investCurrency);
    }

    function _investBought(BalanceDelta delta) internal view returns (uint256) {
        int128 investDelta = investIsToken0 ? delta.amount0() : delta.amount1();
        if (investDelta <= 0) {
            return 0;
        }
        return uint256(int256(investDelta));
    }

    /// @dev Routers must pass the trader in hookData. EOAs swapping directly may use sender.
    function _resolveUser(address sender, bytes calldata hookData) internal view returns (address user) {
        user = _decodeUser(hookData);
        if (user != address(0)) {
            return user;
        }
        if (sender.code.length == 0) {
            return sender;
        }
        return address(0);
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
}
