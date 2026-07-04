// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @title DeployPool
 * @notice Initializes an INVEST/WETH Uniswap v4 pool with the Investing hook.
 * @dev Run after DeployInvesting. Requires POOL_MANAGER, HOOK_ADDRESS, INVEST_TOKEN, WETH_ADDRESS.
 */
contract DeployPool is Script {
    function run() public {
        address poolManagerAddr = vm.envAddress("POOL_MANAGER");
        address hookAddr = vm.envAddress("HOOK_ADDRESS");
        address investToken = vm.envAddress("INVEST_TOKEN");
        address weth = vm.envAddress("WETH_ADDRESS");
        bool investIsToken0 = vm.envOr("INVEST_IS_TOKEN0", true);
        uint24 fee = uint24(vm.envOr("POOL_FEE", uint256(3000)));
        int24 tickSpacing = int24(int256(vm.envOr("TICK_SPACING", uint256(60))));

        Currency currency0 = investIsToken0 ? Currency.wrap(investToken) : Currency.wrap(weth);
        Currency currency1 = investIsToken0 ? Currency.wrap(weth) : Currency.wrap(investToken);

        PoolKey memory key = PoolKey({
            currency0: currency0, currency1: currency1, fee: fee, tickSpacing: tickSpacing, hooks: IHooks(hookAddr)
        });

        vm.startBroadcast();
        IPoolManager(poolManagerAddr).initialize(key, TickMath.getSqrtPriceAtTick(0));
        vm.stopBroadcast();

        console.log("Initialized pool for INVEST/WETH with hook:", hookAddr);
        console.log("currency0:", Currency.unwrap(key.currency0));
        console.log("currency1:", Currency.unwrap(key.currency1));
        console.log("fee:", fee);
    }
}
