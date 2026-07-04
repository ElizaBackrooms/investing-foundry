// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta, toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
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

contract RouterStub {}

/// @notice Twenty end-user scenarios — buys, claims, sells, edge cases, and security paths.
contract InvestingScenariosTest is Test {
    IPoolManager internal manager;
    InvestingSwapRouter internal swapRouter;
    PoolModifyLiquidityTest internal modifyLiquidityRouter;
    InvestingToken internal investToken;
    MockERC20 internal weth;
    InvestingNFT internal nft;
    InvestingHook internal hook;
    PoolKey internal key;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    uint256 internal constant LEVEL = 100_000 ether;

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

        modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1e24, salt: 0}),
            Constants.ZERO_BYTES
        );

        _fundTrader(alice);
        _fundTrader(bob);
        _fundTrader(carol);
    }

    function _fundTrader(address trader) internal {
        weth.mint(trader, 100_000_000 ether);
        vm.prank(trader);
        weth.approve(address(swapRouter), type(uint256).max);
    }

    function _simulateBuy(address user, uint256 investAmount) internal {
        BalanceDelta delta = hook.investIsToken0()
            ? toBalanceDelta(int128(int256(investAmount)), 0)
            : toBalanceDelta(0, int128(int256(investAmount)));

        vm.prank(address(manager));
        hook.afterSwap(user, key, _swapParams(), delta, abi.encode(user));
    }

    function _swapParams() internal pure returns (SwapParams memory) {
        return SwapParams({zeroForOne: false, amountSpecified: -1, sqrtPriceLimitX96: 0});
    }

    function _buyWeth(address user, uint128 wethIn) internal {
        vm.prank(user);
        swapRouter.buyInvestWithWeth(key, wethIn);
    }

    function _claim(address user) internal {
        vm.prank(user);
        nft.claimNextFeather();
    }

    // 1. Brand-new user buys enough to unlock the first gold feather.
    function test_scenario01_newUserClaimsFirstGoldFeather() public {
        _simulateBuy(alice, LEVEL);
        _claim(alice);

        assertEq(nft.balanceOf(alice), 1);
        assertEq(nft.highestLevel(alice), 1);
        assertEq(nft.tokenIdToLevel(0), 1);
    }

    // 2. Two smaller buys add up to one feather level.
    function test_scenario02_twoBuysSumToOneLevel() public {
        _simulateBuy(alice, 60_000 ether);
        _simulateBuy(alice, 40_000 ether);
        _claim(alice);

        assertEq(nft.balanceOf(alice), 1);
        assertEq(nft.investAccumulated(alice), LEVEL);
    }

    // 3. One large buy unlocks two feathers in a single claim.
    function test_scenario03_buy200kClaimsTwoFeathers() public {
        _simulateBuy(alice, 2 * LEVEL);
        _claim(alice);

        assertEq(nft.balanceOf(alice), 2);
        assertEq(nft.tokenIdToLevel(0), 1);
        assertEq(nft.tokenIdToLevel(1), 2);
    }

    // 4. Twenty-five levels require two claim transactions (20 cap per tx).
    function test_scenario04_25LevelsRequiresTwoClaimTxs() public {
        _simulateBuy(alice, 25 * LEVEL);
        _claim(alice);
        assertEq(nft.balanceOf(alice), 20);
        assertEq(nft.highestLevel(alice), 20);

        _claim(alice);
        assertEq(nft.balanceOf(alice), 25);
        assertEq(nft.highestLevel(alice), 25);
    }

    // 5. Two users' buy volumes stay independent.
    function test_scenario05_twoUsersIndependentVolume() public {
        _simulateBuy(alice, 3 * LEVEL);
        _simulateBuy(bob, 5 * LEVEL);

        assertEq(nft.eligibleLevel(alice), 3);
        assertEq(nft.eligibleLevel(bob), 5);

        _claim(alice);
        _claim(bob);

        assertEq(nft.balanceOf(alice), 3);
        assertEq(nft.balanceOf(bob), 5);
    }

    // 6. Receiving gifted INVEST does not give feather progress to the recipient.
    function test_scenario06_giftedTokensDontCountForRecipient() public {
        _simulateBuy(alice, 2 * LEVEL);
        investToken.transfer(bob, 2 * LEVEL);

        _claim(bob);
        assertEq(nft.balanceOf(bob), 0);
        assertEq(nft.investAccumulated(bob), 0);
    }

    // 7. Selling after buying keeps earned volume (real router sell path).
    function test_scenario07_sellAfterBuyKeepsVolume() public {
        _simulateBuy(alice, 2 * LEVEL);
        investToken.transfer(alice, 2 * LEVEL);

        uint256 volume = nft.investAccumulated(alice);
        assertEq(nft.eligibleLevel(alice), 2);

        vm.startPrank(alice);
        investToken.approve(address(swapRouter), 2 * LEVEL);
        swapRouter.sellInvestForWeth(key, uint128(LEVEL));
        vm.stopPrank();

        assertEq(nft.investAccumulated(alice), volume);
        _claim(alice);
        assertEq(nft.balanceOf(alice), 2);
    }

    // 8. A dust swap is ignored; the next real swap counts.
    function test_scenario08_dustSwapThenRealSwap() public {
        _simulateBuy(alice, InvestingConfig.MIN_SWAP_VOLUME - 1);
        assertEq(nft.investAccumulated(alice), 0);

        _simulateBuy(alice, LEVEL);
        assertEq(nft.eligibleLevel(alice), 1);
    }

    // 9. A contract calling the pool without hookData earns no volume.
    function test_scenario09_contractRouterNoCredit() public {
        RouterStub router = new RouterStub();
        BalanceDelta delta =
            hook.investIsToken0() ? toBalanceDelta(int128(int256(LEVEL)), 0) : toBalanceDelta(0, int128(int256(LEVEL)));

        vm.prank(address(manager));
        hook.afterSwap(address(router), key, _swapParams(), delta, "");

        assertEq(nft.investAccumulated(address(router)), 0);
    }

    // 10. Claiming with zero buy history is a no-op.
    function test_scenario10_noVolumeNoClaim() public {
        _claim(alice);
        assertEq(nft.balanceOf(alice), 0);
        assertEq(nft.highestLevel(alice), 0);
    }

    // 11. Claiming again when already caught up does nothing extra.
    function test_scenario11_doubleClaimWhenCaughtUp() public {
        _simulateBuy(alice, LEVEL);
        _claim(alice);
        _claim(alice);
        assertEq(nft.balanceOf(alice), 1);
    }

    // 12. Feather NFTs are transferable to another wallet.
    function test_scenario12_featherNftIsTransferable() public {
        _simulateBuy(alice, LEVEL);
        _claim(alice);

        vm.prank(alice);
        nft.transferFrom(alice, carol, 0);

        assertEq(nft.ownerOf(0), carol);
        assertEq(nft.balanceOf(carol), 1);
        assertEq(nft.balanceOf(alice), 0);
    }

    // 13. Exactly the minimum swap threshold (1k INVEST) counts once.
    function test_scenario13_minimumSwapExactly1000Counts() public {
        _simulateBuy(alice, InvestingConfig.MIN_SWAP_VOLUME);
        assertEq(nft.investAccumulated(alice), InvestingConfig.MIN_SWAP_VOLUME);
    }

    // 14. Level 25 is a milestone — metadata differs from a normal level.
    function test_scenario14_level25MilestoneMetadata() public {
        _simulateBuy(alice, 25 * LEVEL);
        _claim(alice);
        _claim(alice);

        string memory level2 = nft.tokenURI(1);
        string memory level25 = nft.tokenURI(24);
        assertNotEq(level2, level25);
    }

    // 15. Sequential levels mint in order (1, 2, 3).
    function test_scenario15_sequentialLevelsMintInOrder() public {
        _simulateBuy(alice, 3 * LEVEL);
        _claim(alice);

        assertEq(nft.tokenIdToLevel(0), 1);
        assertEq(nft.tokenIdToLevel(1), 2);
        assertEq(nft.tokenIdToLevel(2), 3);
    }

    // 16. Partial progress (50k + 50k) only unlocks after the second buy.
    function test_scenario16_partialAccumulationAcrossSwaps() public {
        _simulateBuy(alice, 50_000 ether);
        assertEq(nft.eligibleLevel(alice), 0);

        _simulateBuy(alice, 50_000 ether);
        assertEq(nft.eligibleLevel(alice), 1);
    }

    // 17. Buying on a non-canonical pool reverts.
    function test_scenario17_wrongPoolReverts() public {
        MockERC20 scam = new MockERC20("SCAM", "SCAM", 18);
        bool scamFirst = address(scam) < address(weth);
        PoolKey memory badKey = PoolKey({
            currency0: Currency.wrap(scamFirst ? address(scam) : address(weth)),
            currency1: Currency.wrap(scamFirst ? address(weth) : address(scam)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });

        vm.prank(alice);
        vm.expectRevert(InvestingSwapRouter.InvalidPool.selector);
        swapRouter.buyInvestWithWeth(badKey, uint128(LEVEL));
    }

    // 18. Zero-amount swap reverts.
    function test_scenario18_zeroSwapReverts() public {
        vm.prank(alice);
        vm.expectRevert(InvestingSwapRouter.ZeroAmount.selector);
        swapRouter.buyInvestWithWeth(key, 0);
    }

    // 19. eligibleLevel preview is correct after a large buy.
    function test_scenario19_eligibleLevelPreviewAfterBuy() public {
        _simulateBuy(alice, 5 * LEVEL);
        assertEq(nft.eligibleLevel(alice), 5);
        assertEq(nft.highestLevel(alice), 0);
    }

    // 20. Full buy → claim → buy more → claim again lifecycle.
    function test_scenario20_buyClaimBuyAgainLifecycle() public {
        _simulateBuy(alice, LEVEL);
        _claim(alice);
        assertEq(nft.balanceOf(alice), 1);

        _buyWeth(alice, uint128(LEVEL / 10));
        assertGt(nft.investAccumulated(alice), LEVEL);

        _simulateBuy(alice, 3 * LEVEL);
        _claim(alice);

        assertEq(nft.balanceOf(alice), 4);
        assertEq(nft.highestLevel(alice), 4);
    }
}
