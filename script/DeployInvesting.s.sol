// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import "../src/InvestingToken.sol";
import "../src/InvestingHook.sol";
import "../src/InvestingNFT.sol";
import "../src/InvestingSwapRouter.sol";
import "../src/utils/HookMiner.sol";

/**
 * @title DeployInvesting
 * @notice Deployment script for the Investing project on Robinhood Chain
 */
contract DeployInvesting is Script {
    function run() public {
        vm.startBroadcast();

        InvestingToken investingToken = new InvestingToken();
        InvestingNFT investingNFT = new InvestingNFT();

        address weth = vm.envAddress("WETH_ADDRESS");
        address poolManagerAddr = vm.envOr("POOL_MANAGER", address(0));
        IPoolManager poolManager =
            poolManagerAddr == address(0) ? new PoolManager(address(this)) : IPoolManager(poolManagerAddr);

        (address hookAddress, bytes32 salt) = HookMiner.find(
            address(this),
            uint160(Hooks.AFTER_SWAP_FLAG),
            type(InvestingHook).creationCode,
            abi.encode(poolManager, address(investingNFT), address(investingToken), weth)
        );

        InvestingHook investingHook =
            new InvestingHook{salt: salt}(poolManager, address(investingNFT), address(investingToken), weth);
        require(address(investingHook) == hookAddress, "hook address mismatch");

        investingNFT.setHook(address(investingHook));
        InvestingSwapRouter swapRouter = new InvestingSwapRouter(poolManager, address(investingToken), weth);

        bool investIsToken0 = address(investingToken) < weth;
        Currency currency0 = investIsToken0 ? Currency.wrap(address(investingToken)) : Currency.wrap(weth);
        Currency currency1 = investIsToken0 ? Currency.wrap(weth) : Currency.wrap(address(investingToken));
        uint24 poolFee = uint24(vm.envOr("POOL_FEE", uint256(3000)));
        int24 tickSpacing = int24(int256(vm.envOr("TICK_SPACING", uint256(60))));

        _writeDeployment(
            block.chainid,
            address(investingToken),
            address(investingNFT),
            address(poolManager),
            address(investingHook),
            address(swapRouter),
            weth,
            Currency.unwrap(currency0),
            Currency.unwrap(currency1),
            poolFee,
            tickSpacing,
            investIsToken0,
            salt
        );

        console.log("Deployed InvestingToken at:", address(investingToken));
        console.log("Deployed InvestingNFT at:", address(investingNFT));
        console.log("Deployed PoolManager at:", address(poolManager));
        console.log("Deployed InvestingHook at:", address(investingHook));
        console.log("Deployed InvestingSwapRouter at:", address(swapRouter));
        console.log("Wrote deployments/latest.json");
        console.log("Initialize the INVEST/WETH pool with DeployPool.s.sol");

        vm.stopBroadcast();
    }

    function _writeDeployment(
        uint256 chainId,
        address investToken,
        address investNft,
        address poolManager,
        address hook,
        address swapRouter,
        address weth,
        address currency0,
        address currency1,
        uint24 poolFee,
        int24 tickSpacing,
        bool investIsToken0,
        bytes32 hookSalt
    ) internal {
        string memory obj = "deployment";
        vm.serializeUint(obj, "chainId", chainId);
        vm.serializeAddress(obj, "investToken", investToken);
        vm.serializeAddress(obj, "investNft", investNft);
        vm.serializeAddress(obj, "poolManager", poolManager);
        vm.serializeAddress(obj, "hook", hook);
        vm.serializeAddress(obj, "swapRouter", swapRouter);
        vm.serializeAddress(obj, "weth", weth);
        vm.serializeAddress(obj, "currency0", currency0);
        vm.serializeAddress(obj, "currency1", currency1);
        vm.serializeUint(obj, "poolFee", poolFee);
        vm.serializeInt(obj, "tickSpacing", tickSpacing);
        vm.serializeBool(obj, "investIsToken0", investIsToken0);
        string memory json = vm.serializeBytes32(obj, "hookSalt", hookSalt);
        vm.writeJson(json, "./deployments/latest.json");
    }
}
