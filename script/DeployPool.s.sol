// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
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
        uint24 fee = uint24(vm.envOr("POOL_FEE", uint256(3000)));
        int24 tickSpacing = int24(int256(vm.envOr("TICK_SPACING", uint256(60))));
        int24 initTick = int24(int256(vm.envOr("INIT_TICK", uint256(0))));

        require(investToken != weth, "identical tokens");

        Currency currency0 = investToken < weth ? Currency.wrap(investToken) : Currency.wrap(weth);
        Currency currency1 = investToken < weth ? Currency.wrap(weth) : Currency.wrap(investToken);

        PoolKey memory key = PoolKey({
            currency0: currency0, currency1: currency1, fee: fee, tickSpacing: tickSpacing, hooks: IHooks(hookAddr)
        });

        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(initTick);

        vm.startBroadcast();
        IPoolManager(poolManagerAddr).initialize(key, sqrtPriceX96);
        vm.stopBroadcast();

        PoolId poolId = key.toId();
        _appendPoolToDeployment(poolId, initTick, sqrtPriceX96);

        console.log("Initialized pool for INVEST/WETH with hook:", hookAddr);
        console.log("currency0:", Currency.unwrap(key.currency0));
        console.log("currency1:", Currency.unwrap(key.currency1));
        console.log("fee:", fee);
        console.log("initTick:", initTick);
        console.logBytes32(PoolId.unwrap(poolId));
    }

    function _appendPoolToDeployment(PoolId poolId, int24 initTick, uint160 sqrtPriceX96) internal {
        string memory path = "./deployments/latest.json";
        if (!vm.exists(path)) {
            console.log("deployments/latest.json not found; skipping manifest update");
            return;
        }

        vm.writeJson("true", path, ".poolInitialized");
        vm.writeJson(vm.toString(uint256(int256(initTick))), path, ".initializeTick");
        vm.writeJson(vm.toString(uint256(sqrtPriceX96)), path, ".initializeSqrtPriceX96");
        vm.writeJson(_quotedBytes32(PoolId.unwrap(poolId)), path, ".poolId");
        console.log("Updated deployments/latest.json with pool initialization metadata");
    }

    function _quotedBytes32(bytes32 value) internal view returns (string memory) {
        return string.concat('"', vm.toString(value), '"');
    }
}
