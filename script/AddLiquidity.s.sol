// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title AddLiquidity
 * @notice Adds initial liquidity to an initialized INVEST/WETH v4 pool via PoolModifyLiquidityTest.
 * @dev Run after DeployPool. Set POOL_MANAGER, INVEST_TOKEN, WETH_ADDRESS, HOOK_ADDRESS, and liquidity env vars.
 */
contract AddLiquidity is Script {
    using StateLibrary for IPoolManager;

    function run() public {
        address poolManagerAddr = vm.envAddress("POOL_MANAGER");
        address hookAddr = vm.envAddress("HOOK_ADDRESS");
        address investToken = vm.envAddress("INVEST_TOKEN");
        address weth = vm.envAddress("WETH_ADDRESS");
        uint24 fee = uint24(vm.envOr("POOL_FEE", uint256(3000)));
        int24 tickSpacing = int24(int256(vm.envOr("TICK_SPACING", uint256(60))));

        int24 tickLower = int24(int256(vm.envOr("TICK_LOWER", uint256(int256(-120)))));
        int24 tickUpper = int24(int256(vm.envOr("TICK_UPPER", uint256(int256(120)))));

        require(investToken != weth, "identical tokens");
        require(tickLower < tickUpper, "invalid tick range");

        Currency currency0 = investToken < weth ? Currency.wrap(investToken) : Currency.wrap(weth);
        Currency currency1 = investToken < weth ? Currency.wrap(weth) : Currency.wrap(investToken);

        PoolKey memory key = PoolKey({
            currency0: currency0, currency1: currency1, fee: fee, tickSpacing: tickSpacing, hooks: IHooks(hookAddr)
        });

        IPoolManager poolManager = IPoolManager(poolManagerAddr);
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(key.toId());
        require(sqrtPriceX96 != 0, "pool not initialized");

        int128 liquidityDelta = _resolveLiquidityDelta(sqrtPriceX96, tickLower, tickUpper, investToken, weth);

        vm.startBroadcast();

        address routerAddr = vm.envOr("MODIFY_LIQUIDITY_ROUTER", address(0));
        PoolModifyLiquidityTest router;
        if (routerAddr == address(0)) {
            router = new PoolModifyLiquidityTest(poolManager);
            console.log("Deployed PoolModifyLiquidityTest at:", address(router));
        } else {
            router = PoolModifyLiquidityTest(routerAddr);
            console.log("Using PoolModifyLiquidityTest at:", routerAddr);
        }

        IERC20(Currency.unwrap(currency0)).approve(address(router), type(uint256).max);
        IERC20(Currency.unwrap(currency1)).approve(address(router), type(uint256).max);

        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: tickLower, tickUpper: tickUpper, liquidityDelta: liquidityDelta, salt: 0
        });

        router.modifyLiquidity(key, params, Constants.ZERO_BYTES);

        vm.stopBroadcast();

        _appendLiquidityToDeployment(tickLower, tickUpper, liquidityDelta, address(router));

        console.log("Added liquidity to INVEST/WETH pool");
        console.log("tickLower:", tickLower);
        console.log("tickUpper:", tickUpper);
        console.log("liquidityDelta:", uint256(int256(liquidityDelta)));
    }

    function _resolveLiquidityDelta(
        uint160 sqrtPriceX96,
        int24 tickLower,
        int24 tickUpper,
        address investToken,
        address weth
    ) internal view returns (int128 liquidityDelta) {
        uint256 directDelta = vm.envOr("LIQUIDITY_DELTA", uint256(0));
        if (directDelta > 0) {
            require(directDelta <= uint128(type(int128).max), "liquidity overflow");
            return int128(int256(directDelta));
        }

        uint256 amountInvest = vm.envOr("LIQUIDITY_INVEST", uint256(0));
        uint256 amountWeth = vm.envOr("LIQUIDITY_WETH", uint256(0));
        uint256 singleAmount = vm.envOr("LIQUIDITY_AMOUNT", uint256(0));

        if (singleAmount > 0) {
            amountInvest = singleAmount;
            amountWeth = singleAmount;
        }

        require(amountInvest > 0 && amountWeth > 0, "set LIQUIDITY_DELTA or token amounts");

        uint256 amount0 = investToken < weth ? amountInvest : amountWeth;
        uint256 amount1 = investToken < weth ? amountWeth : amountInvest;

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            amount0,
            amount1
        );

        require(liquidity > 0, "zero liquidity");
        return int128(liquidity);
    }

    function _appendLiquidityToDeployment(
        int24 tickLower,
        int24 tickUpper,
        int128 liquidityDelta,
        address modifyLiquidityRouter
    ) internal {
        string memory path = "./deployments/latest.json";
        if (!vm.exists(path)) {
            console.log("deployments/latest.json not found; skipping manifest update");
            return;
        }

        vm.writeJson("true", path, ".liquidityAdded");
        vm.writeJson(vm.toString(uint256(int256(tickLower))), path, ".liquidityTickLower");
        vm.writeJson(vm.toString(uint256(int256(tickUpper))), path, ".liquidityTickUpper");
        vm.writeJson(vm.toString(uint256(int256(liquidityDelta))), path, ".liquidityDelta");
        vm.writeJson(_quotedAddress(modifyLiquidityRouter), path, ".modifyLiquidityRouter");
        console.log("Updated deployments/latest.json with liquidity metadata");
    }

    function _quotedAddress(address value) internal view returns (string memory) {
        return string.concat('"', vm.toString(value), '"');
    }
}
