// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta, toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import "../src/InvestingToken.sol";
import "../src/InvestingNFT.sol";
import "../src/InvestingHook.sol";
import "../src/InvestingConfig.sol";
import "../src/utils/HookMiner.sol";

contract ReentrantClaimer {
    InvestingNFT public nft;
    uint256 public reentryCount;

    constructor(InvestingNFT _nft) {
        nft = _nft;
    }

    function claim() external {
        nft.claimNextFeather();
    }

    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4) {
        if (reentryCount == 0) {
            reentryCount++;
            nft.claimNextFeather();
        }
        return IERC721Receiver.onERC721Received.selector;
    }
}

interface IERC721Receiver {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        returns (bytes4);
}

contract RouterStub {}

contract InvestingTest is Test {
    InvestingToken internal token;
    MockERC20 internal weth;
    InvestingNFT internal nft;
    InvestingHook internal hook;
    IPoolManager internal manager;

    address internal alice = makeAddr("alice");

    uint256 internal constant LEVEL = 100_000 ether;

    function setUp() public {
        token = new InvestingToken();
        weth = new MockERC20("WETH", "WETH", 18);
        nft = new InvestingNFT();
        manager = new PoolManager(address(this));

        (address hookAddress, bytes32 salt) = HookMiner.find(
            address(this),
            uint160(Hooks.AFTER_SWAP_FLAG),
            type(InvestingHook).creationCode,
            abi.encode(manager, address(nft), address(token), address(weth))
        );

        hook = new InvestingHook{salt: salt}(manager, address(nft), address(token), address(weth));
        assertEq(address(hook), hookAddress);
        nft.setHook(address(hook));
    }

    function _poolKey() internal view returns (PoolKey memory) {
        bool investFirst = address(token) < address(weth);
        return PoolKey({
            currency0: Currency.wrap(investFirst ? address(token) : address(weth)),
            currency1: Currency.wrap(investFirst ? address(weth) : address(token)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
    }

    function _swapParams() internal pure returns (SwapParams memory) {
        return SwapParams({zeroForOne: false, amountSpecified: -int256(1), sqrtPriceLimitX96: 0});
    }

    function _simulateInvestBuy(address user, uint256 amount) internal {
        BalanceDelta delta = hook.investIsToken0()
            ? toBalanceDelta(int128(int256(amount)), 0)
            : toBalanceDelta(0, int128(int256(amount)));
        vm.prank(address(manager));
        hook.afterSwap(user, _poolKey(), _swapParams(), delta, abi.encode(user));
    }

    function test_tokenMaxSupply() public view {
        assertEq(token.totalSupply(), 1_000_000_000 * 10 ** token.decimals());
        assertEq(token.MAX_SUPPLY(), 1_000_000_000 ether);
    }

    function test_claimNextFeather_mintsBasedOnSwapVolume() public {
        _simulateInvestBuy(alice, 3 * LEVEL);

        vm.prank(alice);
        nft.claimNextFeather();

        assertEq(nft.balanceOf(alice), 3);
        assertEq(nft.highestLevel(alice), 3);
        assertEq(nft.tokenIdToLevel(0), 1);
        assertEq(nft.tokenIdToLevel(2), 3);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_partialVolumeBelowOneLevelDoesNotClaim() public {
        _simulateInvestBuy(alice, LEVEL - 1);

        vm.prank(alice);
        nft.claimNextFeather();

        assertEq(nft.eligibleLevel(alice), 0);
        assertEq(nft.balanceOf(alice), 0);
    }

    function test_claimNextFeather_worksAfterSellingTokens() public {
        _simulateInvestBuy(alice, 5 * LEVEL);
        token.transfer(alice, 5 * LEVEL);

        vm.prank(alice);
        token.transfer(address(0xdead), 5 * LEVEL);
        assertEq(token.balanceOf(alice), 0);

        vm.prank(alice);
        nft.claimNextFeather();

        assertEq(nft.balanceOf(alice), 5);
        assertEq(nft.highestLevel(alice), 5);
    }

    function test_claimNextFeather_noopWhenAlreadyCaughtUp() public {
        _simulateInvestBuy(alice, 2 * LEVEL);

        vm.startPrank(alice);
        nft.claimNextFeather();
        nft.claimNextFeather();
        vm.stopPrank();

        assertEq(nft.balanceOf(alice), 2);
    }

    function test_claimNextFeather_batchMintsOnAdditionalSwaps() public {
        _simulateInvestBuy(alice, 1 * LEVEL);

        vm.prank(alice);
        nft.claimNextFeather();
        assertEq(nft.balanceOf(alice), 1);

        _simulateInvestBuy(alice, 4 * LEVEL);

        vm.prank(alice);
        nft.claimNextFeather();

        assertEq(nft.balanceOf(alice), 5);
        assertEq(nft.highestLevel(alice), 5);
        assertEq(nft.investAccumulated(alice), 5 * LEVEL);
    }

    function test_claimNextFeather_emitsFeatherClaimed() public {
        _simulateInvestBuy(alice, 2 * LEVEL);

        vm.startPrank(alice);
        vm.expectEmit(true, true, false, true);
        emit InvestingNFT.FeatherClaimed(alice, 0, 1);
        vm.expectEmit(true, true, false, true);
        emit InvestingNFT.FeatherClaimed(alice, 1, 2);
        nft.claimNextFeather();
        vm.stopPrank();
    }

    function test_claimNextFeather_blocksReentrancy() public {
        ReentrantClaimer claimer = new ReentrantClaimer(nft);
        _simulateInvestBuy(address(claimer), 3 * LEVEL);

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        claimer.claim();

        assertEq(nft.balanceOf(address(claimer)), 0);
    }

    function test_claimNextFeather_respectsMaxPerTx() public {
        _simulateInvestBuy(alice, 25 * LEVEL);

        vm.prank(alice);
        nft.claimNextFeather();

        assertEq(nft.balanceOf(alice), InvestingConfig.MAX_CLAIM_PER_TX);
        assertEq(nft.highestLevel(alice), InvestingConfig.MAX_CLAIM_PER_TX);
        assertEq(nft.eligibleLevel(alice), 25);
    }

    function test_claimNextFeather_revertsWithoutSwapVolume() public {
        vm.prank(alice);
        nft.claimNextFeather();
        assertEq(nft.balanceOf(alice), 0);
    }

    function test_recordInvestFromSwap_onlyHook() public {
        vm.expectRevert(InvestingNFT.OnlyHook.selector);
        nft.recordInvestFromSwap(alice, 1 * LEVEL);
    }

    function test_tokenURI_returnsJsonMetadata() public {
        _simulateInvestBuy(alice, 1 * LEVEL);

        vm.prank(alice);
        nft.claimNextFeather();

        string memory uri = nft.tokenURI(0);
        assertTrue(bytes(uri).length > 0);
        assertEq(_prefix(uri, 29), "data:application/json;base64,");
    }

    function test_tokenURI_level1UsesGoldMilestone() public {
        _simulateInvestBuy(alice, 2 * LEVEL);

        vm.prank(alice);
        nft.claimNextFeather();

        string memory level1Uri = nft.tokenURI(0);
        string memory level2Uri = nft.tokenURI(1);

        assertTrue(_contains(level1Uri, "data:application/json;base64,"));
        assertNotEq(level1Uri, level2Uri);
    }

    function test_tokenURI_milestoneGlowAtLevel10() public {
        _simulateInvestBuy(alice, 10 * LEVEL);

        vm.prank(alice);
        nft.claimNextFeather();

        string memory level10Uri = nft.tokenURI(9);
        assertTrue(_contains(level10Uri, "RGVjYWRl"));
    }

    function test_hook_recordsVolumeWithoutMinting() public {
        BalanceDelta delta = hook.investIsToken0()
            ? toBalanceDelta(int128(int256(3 * LEVEL)), 0)
            : toBalanceDelta(0, int128(int256(3 * LEVEL)));

        vm.prank(address(manager));
        vm.expectEmit(true, false, false, true);
        emit InvestingHook.SwapOccurred(alice, delta.amount0(), delta.amount1());

        vm.expectEmit(true, false, false, true);
        emit InvestingHook.InvestRecorded(alice, 3 * LEVEL, 3);

        hook.afterSwap(alice, _poolKey(), _swapParams(), delta, abi.encode(alice));

        assertEq(nft.balanceOf(alice), 0);
        assertEq(nft.eligibleLevel(alice), 3);
    }

    function test_hook_ignoresSells() public {
        BalanceDelta delta = hook.investIsToken0()
            ? toBalanceDelta(-int128(int256(3 * LEVEL)), 0)
            : toBalanceDelta(0, -int128(int256(3 * LEVEL)));

        vm.prank(address(manager));
        hook.afterSwap(alice, _poolKey(), _swapParams(), delta, abi.encode(alice));

        assertEq(nft.investAccumulated(alice), 0);
    }

    function test_hook_skipsDustBelowMinSwapVolume() public {
        uint256 dust = InvestingConfig.MIN_SWAP_VOLUME - 1;
        BalanceDelta delta =
            hook.investIsToken0() ? toBalanceDelta(int128(int256(dust)), 0) : toBalanceDelta(0, int128(int256(dust)));

        vm.prank(address(manager));
        hook.afterSwap(alice, _poolKey(), _swapParams(), delta, abi.encode(alice));

        assertEq(nft.investAccumulated(alice), 0);
    }

    function test_hook_ignoresInvalidPool() public {
        MockERC20 scam = new MockERC20("SCAM", "SCAM", 18);
        bool scamFirst = address(scam) < address(weth);
        PoolKey memory badKey = PoolKey({
            currency0: Currency.wrap(scamFirst ? address(scam) : address(weth)),
            currency1: Currency.wrap(scamFirst ? address(weth) : address(scam)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
        BalanceDelta delta =
            hook.investIsToken0() ? toBalanceDelta(int128(int256(LEVEL)), 0) : toBalanceDelta(0, int128(int256(LEVEL)));

        vm.prank(address(manager));
        hook.afterSwap(alice, badKey, _swapParams(), delta, abi.encode(alice));

        assertEq(nft.investAccumulated(alice), 0);
    }

    function test_hook_ignoresRouterWithoutHookData() public {
        RouterStub router = new RouterStub();
        BalanceDelta delta =
            hook.investIsToken0() ? toBalanceDelta(int128(int256(LEVEL)), 0) : toBalanceDelta(0, int128(int256(LEVEL)));

        vm.prank(address(manager));
        hook.afterSwap(address(router), _poolKey(), _swapParams(), delta, "");

        assertEq(nft.investAccumulated(alice), 0);
    }

    function test_hook_usesSenderWhenHookDataMissing() public {
        BalanceDelta delta =
            hook.investIsToken0() ? toBalanceDelta(int128(int256(LEVEL)), 0) : toBalanceDelta(0, int128(int256(LEVEL)));

        vm.prank(address(manager));
        hook.afterSwap(alice, _poolKey(), _swapParams(), delta, "");

        assertEq(nft.investAccumulated(alice), LEVEL);
    }

    function test_hook_onlyPoolManager() public {
        BalanceDelta delta =
            hook.investIsToken0() ? toBalanceDelta(int128(int256(LEVEL)), 0) : toBalanceDelta(0, int128(int256(LEVEL)));

        vm.expectRevert(InvestingHook.OnlyPoolManager.selector);
        hook.afterSwap(alice, _poolKey(), _swapParams(), delta, abi.encode(alice));
    }

    function test_setHook_onlyDeployer() public {
        InvestingNFT freshNft = new InvestingNFT();

        vm.prank(makeAddr("attacker"));
        vm.expectRevert(InvestingNFT.OnlyDeployer.selector);
        freshNft.setHook(address(hook));
    }

    function test_setHook_onlyOnce() public {
        vm.expectRevert(InvestingNFT.HookAlreadySet.selector);
        nft.setHook(makeAddr("other"));
    }

    function test_constructor_revertsOnZeroAddresses() public {
        vm.expectRevert(InvestingHook.NftZero.selector);
        new InvestingHook(manager, address(0), address(token), address(weth));

        vm.expectRevert(InvestingHook.SameToken.selector);
        new InvestingHook(manager, address(nft), address(token), address(token));

        vm.expectRevert(InvestingHook.PoolManagerZero.selector);
        new InvestingHook(IPoolManager(address(0)), address(nft), address(token), address(weth));

        InvestingNFT freshNft = new InvestingNFT();
        vm.expectRevert(InvestingNFT.HookZero.selector);
        freshNft.setHook(address(0));
    }

    function _prefix(string memory value, uint256 length) internal pure returns (string memory) {
        bytes memory valueBytes = bytes(value);
        bytes memory prefix = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            prefix[i] = valueBytes[i];
        }
        return string(prefix);
    }

    function _contains(string memory haystack, string memory needle) internal pure returns (bool) {
        bytes memory haystackBytes = bytes(haystack);
        bytes memory needleBytes = bytes(needle);

        if (needleBytes.length > haystackBytes.length) {
            return false;
        }

        for (uint256 i = 0; i <= haystackBytes.length - needleBytes.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < needleBytes.length; j++) {
                if (haystackBytes[i + j] != needleBytes[j]) {
                    found = false;
                    break;
                }
            }
            if (found) {
                return true;
            }
        }

        return false;
    }
}
