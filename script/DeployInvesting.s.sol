// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
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
        InvestingSwapRouter swapRouter = new InvestingSwapRouter(poolManager);

        console.log("Deployed InvestingToken at:", address(investingToken));
        console.log("Deployed InvestingNFT at:", address(investingNFT));
        console.log("Deployed PoolManager at:", address(poolManager));
        console.log("Deployed InvestingHook at:", address(investingHook));
        console.log("Deployed InvestingSwapRouter at:", address(swapRouter));
        console.log("Hook salt:", vm.toString(salt));
        console.log("INVEST is token0:", address(investingToken) < weth);
        console.log("Initialize the INVEST/WETH pool with DeployPool.s.sol");

        vm.stopBroadcast();
    }
}
