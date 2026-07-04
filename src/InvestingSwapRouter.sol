// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IERC20Minimal} from "@uniswap/v4-core/src/interfaces/external/IERC20Minimal.sol";

/**
 * @title InvestingSwapRouter
 * @notice Swaps on the canonical INVEST pool and auto-attributes volume to msg.sender.
 */
contract InvestingSwapRouter is IUnlockCallback {
    IPoolManager public immutable manager;
    address public immutable investToken;
    address public immutable weth;
    bool public immutable investIsToken0;

    struct CallbackData {
        address sender;
        PoolKey key;
        SwapParams params;
    }

    error OnlyPoolManager();
    error InvalidPool();
    error ZeroAmount();
    error TokenZero();

    constructor(IPoolManager _manager, address _investToken, address _weth) {
        if (_investToken == address(0) || _weth == address(0)) revert TokenZero();
        manager = _manager;
        investToken = _investToken;
        weth = _weth;
        investIsToken0 = _investToken < _weth;
    }

    /// @notice Buy INVEST with an exact WETH input. Volume is credited to msg.sender.
    function buyInvestWithWeth(PoolKey calldata key, uint128 wethAmountIn)
        external
        payable
        returns (BalanceDelta delta)
    {
        if (wethAmountIn == 0) revert ZeroAmount();
        _requireCanonicalPool(key);

        SwapParams memory params = SwapParams({
            zeroForOne: !investIsToken0,
            amountSpecified: -int256(uint256(wethAmountIn)),
            sqrtPriceLimitX96: investIsToken0 ? TickMath.MAX_SQRT_PRICE - 1 : TickMath.MIN_SQRT_PRICE + 1
        });

        return _swap(key, params);
    }

    function swap(PoolKey calldata key, SwapParams calldata params) external payable returns (BalanceDelta delta) {
        _requireCanonicalPool(key);
        return _swap(key, params);
    }

    function _swap(PoolKey calldata key, SwapParams memory params) internal returns (BalanceDelta delta) {
        delta = abi.decode(manager.unlock(abi.encode(CallbackData(msg.sender, key, params))), (BalanceDelta));
    }

    function unlockCallback(bytes calldata rawData) external returns (bytes memory) {
        if (msg.sender != address(manager)) revert OnlyPoolManager();

        CallbackData memory data = abi.decode(rawData, (CallbackData));
        BalanceDelta delta = manager.swap(data.key, data.params, abi.encode(data.sender));

        _settle(data.key, data.sender, delta);
        return abi.encode(delta);
    }

    function _requireCanonicalPool(PoolKey calldata key) internal view {
        address currency0 = Currency.unwrap(key.currency0);
        address currency1 = Currency.unwrap(key.currency1);
        bool matches =
            (currency0 == investToken && currency1 == weth) || (currency0 == weth && currency1 == investToken);
        if (!matches) revert InvalidPool();
    }

    function _settle(PoolKey memory key, address payer, BalanceDelta delta) internal {
        int128 amount0 = delta.amount0();
        int128 amount1 = delta.amount1();

        if (amount0 < 0) {
            _pay(key.currency0, payer, uint256(uint128(-amount0)));
        }
        if (amount1 < 0) {
            _pay(key.currency1, payer, uint256(uint128(-amount1)));
        }
        if (amount0 > 0) {
            manager.take(key.currency0, payer, uint256(uint128(amount0)));
        }
        if (amount1 > 0) {
            manager.take(key.currency1, payer, uint256(uint128(amount1)));
        }
    }

    function _pay(Currency currency, address payer, uint256 amount) internal {
        if (amount == 0) {
            return;
        }
        if (currency.isAddressZero()) {
            manager.settle{value: amount}();
            return;
        }
        manager.sync(currency);
        IERC20Minimal(Currency.unwrap(currency)).transferFrom(payer, address(manager), amount);
        manager.settle();
    }
}
