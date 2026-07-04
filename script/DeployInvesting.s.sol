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
    struct Manifest {
        address investToken;
        address investNft;
        address poolManager;
        address hook;
        address swapRouter;
        address weth;
        address currency0;
        address currency1;
        uint24 poolFee;
        int24 tickSpacing;
        bool investIsToken0;
        bytes32 hookSalt;
    }

    function run() public {
        Manifest memory manifest = _deployContracts();
        _writeDeployment(manifest);
        _logDeployment(manifest);
    }

    function _deployContracts() internal returns (Manifest memory manifest) {
        vm.startBroadcast();

        InvestingToken investingToken = new InvestingToken();
        InvestingNFT investingNFT = new InvestingNFT();

        manifest.weth = vm.envAddress("WETH_ADDRESS");
        address poolManagerAddr = vm.envOr("POOL_MANAGER", address(0));
        IPoolManager poolManager =
            poolManagerAddr == address(0) ? new PoolManager(address(this)) : IPoolManager(poolManagerAddr);

        (address hookAddress, bytes32 salt) = HookMiner.find(
            address(this),
            uint160(Hooks.AFTER_SWAP_FLAG),
            type(InvestingHook).creationCode,
            abi.encode(poolManager, address(investingNFT), address(investingToken), manifest.weth)
        );

        InvestingHook investingHook =
            new InvestingHook{salt: salt}(poolManager, address(investingNFT), address(investingToken), manifest.weth);
        require(address(investingHook) == hookAddress, "hook address mismatch");

        investingNFT.setHook(address(investingHook));
        InvestingSwapRouter swapRouter = new InvestingSwapRouter(poolManager, address(investingToken), manifest.weth);

        manifest.investIsToken0 = address(investingToken) < manifest.weth;
        manifest.currency0 = manifest.investIsToken0 ? address(investingToken) : manifest.weth;
        manifest.currency1 = manifest.investIsToken0 ? manifest.weth : address(investingToken);
        manifest.poolFee = uint24(vm.envOr("POOL_FEE", uint256(3000)));
        manifest.tickSpacing = int24(int256(vm.envOr("TICK_SPACING", uint256(60))));

        manifest.investToken = address(investingToken);
        manifest.investNft = address(investingNFT);
        manifest.poolManager = address(poolManager);
        manifest.hook = address(investingHook);
        manifest.swapRouter = address(swapRouter);
        manifest.hookSalt = salt;

        vm.stopBroadcast();
    }

    function _logDeployment(Manifest memory m) internal view {
        console.log("Deployed InvestingToken at:", m.investToken);
        console.log("Deployed InvestingNFT at:", m.investNft);
        console.log("Deployed PoolManager at:", m.poolManager);
        console.log("Deployed InvestingHook at:", m.hook);
        console.log("Deployed InvestingSwapRouter at:", m.swapRouter);
        console.log("Wrote deployments/latest.json");
        console.log("Initialize the INVEST/WETH pool with DeployPool.s.sol");
    }

    function _writeDeployment(Manifest memory m) internal {
        string memory obj = "deployment";
        vm.serializeUint(obj, "chainId", block.chainid);
        vm.serializeAddress(obj, "investToken", m.investToken);
        vm.serializeAddress(obj, "investNft", m.investNft);
        vm.serializeAddress(obj, "poolManager", m.poolManager);
        vm.serializeAddress(obj, "hook", m.hook);
        vm.serializeAddress(obj, "swapRouter", m.swapRouter);
        vm.serializeAddress(obj, "weth", m.weth);
        vm.serializeAddress(obj, "currency0", m.currency0);
        vm.serializeAddress(obj, "currency1", m.currency1);
        vm.serializeUint(obj, "poolFee", m.poolFee);
        vm.serializeInt(obj, "tickSpacing", m.tickSpacing);
        vm.serializeBool(obj, "investIsToken0", m.investIsToken0);
        string memory json = vm.serializeBytes32(obj, "hookSalt", m.hookSalt);
        vm.writeJson(json, "./deployments/latest.json");
    }
}
