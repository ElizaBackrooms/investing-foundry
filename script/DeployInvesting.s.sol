// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import "../src/InvestingToken.sol";
import "../src/InvestingHook.sol";
import "../src/InvestingNFT.sol";
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

        bool investIsToken0 = vm.envOr("INVEST_IS_TOKEN0", true);
        address poolManagerAddr = vm.envOr("POOL_MANAGER", address(0));
        IPoolManager poolManager =
            poolManagerAddr == address(0) ? new PoolManager(address(this)) : IPoolManager(poolManagerAddr);

        (address hookAddress, bytes32 salt) = HookMiner.find(
            address(this),
            uint160(Hooks.AFTER_SWAP_FLAG),
            type(InvestingHook).creationCode,
            abi.encode(poolManager, address(investingNFT), investIsToken0)
        );

        InvestingHook investingHook = new InvestingHook{salt: salt}(poolManager, address(investingNFT), investIsToken0);
        require(address(investingHook) == hookAddress, "hook address mismatch");

        investingNFT.setHook(address(investingHook));

        console.log("Deployed InvestingToken at:", address(investingToken));
        console.log("Deployed InvestingNFT at:", address(investingNFT));
        console.log("Deployed PoolManager at:", address(poolManager));
        console.log("Deployed InvestingHook at:", address(investingHook));
        console.log("Hook salt:", vm.toString(salt));
        console.log("INVEST is token0:", investIsToken0);
        console.log("Create a Uniswap v4 pool with the hook address above and WETH from WETH_ADDRESS");

        vm.stopBroadcast();
    }
}
