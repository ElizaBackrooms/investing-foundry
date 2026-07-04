// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../src/InvestingToken.sol";
import "../src/InvestingNFT.sol";
import "../src/InvestingHook.sol";

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

contract InvestingTest is Test {
    InvestingToken internal token;
    InvestingNFT internal nft;
    InvestingHook internal hook;

    address internal alice = makeAddr("alice");
    address internal poolManager = makeAddr("poolManager");

    function setUp() public {
        token = new InvestingToken();
        nft = new InvestingNFT();
        hook = new InvestingHook(address(nft), true);
        nft.setHook(address(hook));
    }

    function _simulateInvestBuy(address user, uint256 amount) internal {
        vm.prank(poolManager);
        hook.afterSwap(-int256(amount), 100, 0, 0, 0, 0, 0, 0, abi.encode(user));
    }

    function test_tokenMaxSupply() public view {
        assertEq(token.totalSupply(), 1_000_000_000 * 10 ** token.decimals());
        assertEq(token.MAX_SUPPLY(), 1_000_000_000 ether);
    }

    function test_claimNextFeather_mintsBasedOnSwapVolume() public {
        _simulateInvestBuy(alice, 3 ether);

        vm.prank(alice);
        nft.claimNextFeather();

        assertEq(nft.balanceOf(alice), 3);
        assertEq(nft.highestLevel(alice), 3);
        assertEq(nft.tokenIdToLevel(0), 1);
        assertEq(nft.tokenIdToLevel(2), 3);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_claimNextFeather_worksAfterSellingTokens() public {
        _simulateInvestBuy(alice, 5 ether);
        token.transfer(alice, 5 ether);

        vm.prank(alice);
        token.transfer(address(0xdead), 5 ether);
        assertEq(token.balanceOf(alice), 0);

        vm.prank(alice);
        nft.claimNextFeather();

        assertEq(nft.balanceOf(alice), 5);
        assertEq(nft.highestLevel(alice), 5);
    }

    function test_claimNextFeather_noopWhenAlreadyCaughtUp() public {
        _simulateInvestBuy(alice, 2 ether);

        vm.startPrank(alice);
        nft.claimNextFeather();
        nft.claimNextFeather();
        vm.stopPrank();

        assertEq(nft.balanceOf(alice), 2);
    }

    function test_claimNextFeather_batchMintsOnAdditionalSwaps() public {
        _simulateInvestBuy(alice, 1 ether);

        vm.prank(alice);
        nft.claimNextFeather();
        assertEq(nft.balanceOf(alice), 1);

        _simulateInvestBuy(alice, 4 ether);

        vm.prank(alice);
        nft.claimNextFeather();

        assertEq(nft.balanceOf(alice), 5);
        assertEq(nft.highestLevel(alice), 5);
        assertEq(nft.investAccumulated(alice), 5 ether);
    }

    function test_claimNextFeather_blocksReentrancy() public {
        ReentrantClaimer claimer = new ReentrantClaimer(nft);
        _simulateInvestBuy(address(claimer), 3 ether);

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        claimer.claim();

        assertEq(nft.balanceOf(address(claimer)), 0);
    }

    function test_claimNextFeather_revertsWithoutSwapVolume() public {
        vm.prank(alice);
        nft.claimNextFeather();
        assertEq(nft.balanceOf(alice), 0);
    }

    function test_recordInvestFromSwap_onlyHook() public {
        vm.expectRevert(InvestingNFT.OnlyHook.selector);
        nft.recordInvestFromSwap(alice, 1 ether);
    }

    function test_tokenURI_returnsSvgDataUrl() public {
        _simulateInvestBuy(alice, 1 ether);

        vm.prank(alice);
        nft.claimNextFeather();

        string memory uri = nft.tokenURI(0);
        assertTrue(bytes(uri).length > 0);
        assertEq(_prefix(uri, 19), "data:image/svg+xml,");
    }

    function test_tokenURI_level1IsFullBaseFeather() public {
        _simulateInvestBuy(alice, 2 ether);

        vm.prank(alice);
        nft.claimNextFeather();

        string memory level1Uri = nft.tokenURI(0);
        string memory level2Uri = nft.tokenURI(1);

        assertTrue(_contains(level1Uri, "ellipse"));
        assertTrue(_contains(level1Uri, "%23FFD166"));
        assertTrue(_contains(level2Uri, "ellipse"));
        assertEq(bytes(level1Uri).length, bytes(level2Uri).length);
    }

    function test_hook_recordsVolumeWithoutMinting() public {
        vm.prank(poolManager);
        vm.expectEmit(true, false, false, true);
        emit InvestingHook.SwapOccurred(alice, -3 ether, 100);

        vm.expectEmit(true, false, false, true);
        emit InvestingHook.InvestRecorded(alice, 3 ether, 3);

        hook.afterSwap(-3 ether, 100, 0, 0, 0, 0, 0, 0, abi.encode(alice));

        assertEq(nft.balanceOf(alice), 0);
        assertEq(nft.eligibleLevel(alice), 3);
    }

    function test_hook_ignoresSells() public {
        vm.prank(poolManager);
        hook.afterSwap(3 ether, -100, 0, 0, 0, 0, 0, 0, abi.encode(alice));

        assertEq(nft.investAccumulated(alice), 0);
    }

    function test_hook_skipsEventsWhenHookDataMissing() public {
        vm.recordLogs();
        vm.prank(poolManager);
        hook.afterSwap(-1 ether, 100, 0, 0, 0, 0, 0, 0, "");

        assertEq(vm.getRecordedLogs().length, 0);
    }

    function test_setHook_onlyOnce() public {
        vm.expectRevert(InvestingNFT.HookAlreadySet.selector);
        nft.setHook(makeAddr("other"));
    }

    function test_constructor_revertsOnZeroAddresses() public {
        vm.expectRevert("NFT zero");
        new InvestingHook(address(0), true);

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
