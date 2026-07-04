// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";
import {SortTokens} from "@uniswap/v4-core/test/utils/SortTokens.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import "../src/InvestingToken.sol";
import "../src/InvestingNFT.sol";
import "../src/InvestingHook.sol";
import "../src/InvestingSwapRouter.sol";
import "../src/InvestingConfig.sol";
import "../src/utils/HookMiner.sol";

contract InvestingFuzzTest is Test {
    IPoolManager internal manager;
    InvestingSwapRouter internal swapRouter;
    PoolModifyLiquidityTest internal modifyLiquidityRouter;
    InvestingToken internal investToken;
    MockERC20 internal weth;
    InvestingNFT internal nft;
    InvestingHook internal hook;
    PoolKey internal key;

    address internal trader = makeAddr("trader");

    function setUp() public {
        manager = new PoolManager(address(this));
        modifyLiquidityRouter = new PoolModifyLiquidityTest(manager);

        investToken = new InvestingToken();
        weth = new MockERC20("WETH", "WETH", 18);
        nft = new InvestingNFT();
        swapRouter = new InvestingSwapRouter(manager, address(investToken), address(weth));

        MockERC20 investAsMock = MockERC20(address(investToken));

        (address hookAddress, bytes32 salt) = HookMiner.find(
            address(this),
            uint160(Hooks.AFTER_SWAP_FLAG),
            type(InvestingHook).creationCode,
            abi.encode(manager, address(nft), address(investToken), address(weth))
        );
        hook = new InvestingHook{salt: salt}(manager, address(nft), address(investToken), address(weth));
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

    function testFuzz_buyInvestWithWethAccumulatesVolume(uint128 wethAmountIn) public {
        vm.assume(wethAmountIn >= InvestingConfig.MIN_SWAP_VOLUME);
        vm.assume(wethAmountIn <= 10_000_000 ether);

        uint256 before = nft.investAccumulated(trader);

        vm.prank(trader);
        BalanceDelta delta = swapRouter.buyInvestWithWeth(key, wethAmountIn);

        bool investIsToken0 = Currency.unwrap(key.currency0) == address(investToken);
        int128 investDelta = investIsToken0 ? delta.amount0() : delta.amount1();
        vm.assume(investDelta > 0);
        uint256 investBought = uint256(int256(investDelta));

        uint256 afterBuy = nft.investAccumulated(trader);
        if (investBought >= InvestingConfig.MIN_SWAP_VOLUME) {
            assertEq(afterBuy, before + investBought);
        } else {
            assertEq(afterBuy, before);
        }
    }
}
