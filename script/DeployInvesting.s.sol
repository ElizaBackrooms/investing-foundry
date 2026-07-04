// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/InvestingToken.sol";
import "../src/InvestingHook.sol";
import "../src/InvestingNFT.sol";

/**
 * @title DeployInvesting
 * @notice Deployment script for the Investing project on Robinhood Chain
 */
contract DeployInvesting is Script {
    function run() public {
        vm.startBroadcast();

        InvestingToken investingToken = new InvestingToken();
        InvestingNFT investingNFT = new InvestingNFT();
        // Set true when INVEST is token0 in the pool, false when token1.
        bool investIsToken0 = vm.envOr("INVEST_IS_TOKEN0", true);
        InvestingHook investingHook = new InvestingHook(address(investingNFT), investIsToken0);
        investingNFT.setHook(address(investingHook));

        console.log("Deployed InvestingToken at:", address(investingToken));
        console.log("Deployed InvestingNFT at:", address(investingNFT));
        console.log("Deployed InvestingHook at:", address(investingHook));
        console.log("INVEST is token0:", investIsToken0);
        console.log("Create a Uniswap v4 pool with the hook address above and WETH from WETH_ADDRESS");

        vm.stopBroadcast();
    }
}
