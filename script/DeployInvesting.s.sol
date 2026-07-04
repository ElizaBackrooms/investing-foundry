// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/InvestingToken.sol";
import "../src/InvestingHook.sol";
import "../src/InvestingNFT.sol";
import "@uniswap/v4-core/interfaces/IPoolManager.sol";
import "@uniswap/v4-periphery/contracts/libraries/PoolKey.sol";

/**
 * @title DeployInvesting
 * @notice Deployment script for the Investing project on Robinhood Chain
 */
contract DeployInvesting is Script {
    // Constants for Robinhood Chain
    uint256 private constant ROBINHOOD_CHAIN_ID = 4663; // mainnet
    uint256 private constant ROBINHOOD_TESTNET_CHAIN_ID = 46630; // testnet

    // Addresses on Robinhood Chain mainnet
    address private constant POOL_MANAGER = 0x8366a39cc670b4001a1121b8f6a443a643e40951;
    address private constant POSITION_MANAGER = 0x58daec3116aae6d93017baaea7749052e8a04fa7;

    // Addresses on Robinhood Chain testnet (would need to be verified)
    address private constant TESTNET_POOL_MANAGER = 0x8366a39cc670b4001a1121b8f6a443a643e40951; // Placeholder
    address private constant TESTNET_POSITION_MANAGER = 0x58daec3116aae6d93017baaea7749052e8a04fa7; // Placeholder

    function run(uint256 chainId) public {
        vm.startBroadcast();

        // Determine addresses based on chain
        address poolManager;
        address positionManager;
        if (chainId == ROBINHOOD_TESTNET_CHAIN_ID) {
            poolManager = TESTNET_POOL_MANAGER;
            positionManager = TESTNET_POSITION_MANAGER;
        } else {
            poolManager = POOL_MANAGER;
            positionManager = POSITION_MANAGER;
        }

        // Deploy InvestingToken
        InvestingToken investingToken = new InvestingToken();

        // Deploy InvestingNFT (passing the token address for trust)
        InvestingNFT investingNFT = new InvestingNFT(address(investingToken));

        // Deploy InvestingHook (passing token and NFT addresses)
        InvestingHook investingHook = new InvestingHook(
            address(investingToken),
            address(investingNFT)
        );

        // Get WETH address from environment
        string memory wethAddress = vm.envString("WETH_ADDRESS");
        require(bytes(wethAddress).length > 0, "WETH_ADDRESS not set");
        address weth = address(uint160(uint256(abi.decode(wethAddress, (address)))));

        // Create pool key for INVEST/WETH
        (, address poolAddress,) = PoolKey.encode(
            address(investingToken), // token0
            weth,                    // token1
            500,                     // fee (0.05%)
            int24(-887272),          // tickLower
            int24(887272),           // tickUpper
            poolManager              // hooks (our hook will be attached during pool creation)
        );

        // Create the pool with our hook
        // Note: In practice, you would use the PoolManager's create and initialize functions
        // This is a simplified version - you might need to interact with Uniswap v4 peripherals
        // For now, we'll just note that the pool needs to be created separately
        // with our hook address in the hook field

        console.log("Deployed InvestingToken at:", address(investingToken));
        console.log("Deployed InvestingNFT at:", address(investingNFT));
        console.log("Deployed InvestingHook at:", address(investingHook));
        console.log("Pool will be at (approx):", poolAddress);
        console.log("Please create the pool manually using PoolManager with:");
        console.log("  token0:", address(investingToken));
        console.log("  token1:", weth);
        console.log("  fee: 500");
        console.log("  tickLower: -887272");
        console.log("  tickUpper: 887272");
        console.log("  hook:", address(investingHook));

        vm.stopBroadcast();
    }
}