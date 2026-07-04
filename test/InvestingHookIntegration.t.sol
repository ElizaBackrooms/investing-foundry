// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";
import {SortTokens} from "@uniswap/v4-core/test/utils/SortTokens.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import "../src/InvestingToken.sol";
import "../src/InvestingNFT.sol";
import "../src/InvestingHook.sol";
import "../src/InvestingConfig.sol";
import "../src/utils/HookMiner.sol";

contract InvestingHookIntegrationTest is Test {
    IPoolManager internal manager;
    PoolSwapTest internal swapRouter;
    PoolModifyLiquidityTest internal modifyLiquidityRouter;
    InvestingToken internal investToken;
    MockERC20 internal weth;
    InvestingNFT internal nft;
    InvestingHook internal hook;
    PoolKey internal key;

    address internal trader = makeAddr("trader");
    uint256 internal constant LEVEL = 100_000 ether;

    function setUp() public {
        manager = new PoolManager(address(this));
        swapRouter = new PoolSwapTest(manager);
        modifyLiquidityRouter = new PoolModifyLiquidityTest(manager);

        investToken = new InvestingToken();
        weth = new MockERC20("WETH", "WETH", 18);
        nft = new InvestingNFT();

        MockERC20 investAsMock = MockERC20(address(investToken));
        bool investIsToken0 = address(investAsMock) < address(weth);

        (address hookAddress, bytes32 salt) = HookMiner.find(
            address(this),
            uint160(Hooks.AFTER_SWAP_FLAG),
            type(InvestingHook).creationCode,
            abi.encode(manager, address(nft), investIsToken0)
        );
        hook = new InvestingHook{salt: salt}(manager, address(nft), investIsToken0);
        assertEq(address(hook), hookAddress);
        nft.setHook(address(hook));

        (Currency currency0, Currency currency1) = SortTokens.sort(investAsMock, weth);
        key = PoolKey({
            currency0: currency0, currency1: currency1, fee: 3000, tickSpacing: 60, hooks: IHooks(address(hook))
        });

        manager.initialize(key, TickMath.getSqrtPriceAtTick(0));

        investToken.transfer(address(this), 100_000_000 ether);
        weth.mint(address(this), 100_000_000 ether);
        investToken.approve(address(modifyLiquidityRouter), type(uint256).max);
        weth.approve(address(modifyLiquidityRouter), type(uint256).max);
        weth.mint(trader, 100_000_000 ether);
        vm.prank(trader);
        weth.approve(address(swapRouter), type(uint256).max);

        modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1e24, salt: 0}),
            Constants.ZERO_BYTES
        );
    }

    function test_swapRecordsBuyVolumeThroughPoolManager() public {
        PoolSwapTest.TestSettings memory settings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        bool investIsToken0 = Currency.unwrap(key.currency0) == address(investToken);
        SwapParams memory params = SwapParams({
            zeroForOne: !investIsToken0,
            amountSpecified: int256(LEVEL),
            sqrtPriceLimitX96: investIsToken0 ? TickMath.MAX_SQRT_PRICE - 1 : TickMath.MIN_SQRT_PRICE + 1
        });

        vm.prank(trader);
        swapRouter.swap(key, params, settings, abi.encode(trader));

        assertGt(nft.investAccumulated(trader), InvestingConfig.MIN_SWAP_VOLUME);
        assertEq(nft.balanceOf(trader), 0);
    }
}
