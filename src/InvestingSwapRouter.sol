// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IERC20Minimal} from "@uniswap/v4-core/src/interfaces/external/IERC20Minimal.sol";

/**
 * @title InvestingSwapRouter
 * @notice Swaps on the canonical INVEST pool and auto-attributes volume to msg.sender.
 */
contract InvestingSwapRouter is IUnlockCallback {
    IPoolManager public immutable manager;

    struct CallbackData {
        address sender;
        PoolKey key;
        SwapParams params;
    }

    error OnlyPoolManager();

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    function swap(PoolKey calldata key, SwapParams calldata params) external payable returns (BalanceDelta delta) {
        delta = abi.decode(manager.unlock(abi.encode(CallbackData(msg.sender, key, params))), (BalanceDelta));
    }

    function unlockCallback(bytes calldata rawData) external returns (bytes memory) {
        if (msg.sender != address(manager)) revert OnlyPoolManager();

        CallbackData memory data = abi.decode(rawData, (CallbackData));
        BalanceDelta delta = manager.swap(data.key, data.params, abi.encode(data.sender));

        _settle(data.key, data.sender, delta);
        return abi.encode(delta);
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
