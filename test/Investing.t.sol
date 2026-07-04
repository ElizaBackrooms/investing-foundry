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
        nft = new InvestingNFT(address(token));
        hook = new InvestingHook(address(token), address(nft));
    }

    function test_tokenMaxSupply() public view {
        assertEq(token.totalSupply(), 10_000 * 10 ** token.decimals());
        assertEq(token.balanceOf(address(this)), token.totalSupply());
    }

    function test_claimNextFeather_mintsBasedOnBalance() public {
        token.transfer(alice, 3 ether);

        vm.prank(alice);
        nft.claimNextFeather();

        assertEq(nft.balanceOf(alice), 3);
        assertEq(nft.highestLevel(alice), 3);
        assertEq(nft.tokenIdToLevel(0), 1);
        assertEq(nft.tokenIdToLevel(2), 3);
    }

    function test_claimNextFeather_noopWhenAlreadyCaughtUp() public {
        token.transfer(alice, 2 ether);

        vm.startPrank(alice);
        nft.claimNextFeather();
        nft.claimNextFeather();
        vm.stopPrank();

        assertEq(nft.balanceOf(alice), 2);
    }

    function test_claimNextFeather_batchMintsOnHigherBalance() public {
        token.transfer(alice, 1 ether);

        vm.prank(alice);
        nft.claimNextFeather();
        assertEq(nft.balanceOf(alice), 1);

        token.transfer(alice, 4 ether);

        vm.prank(alice);
        nft.claimNextFeather();

        assertEq(nft.balanceOf(alice), 5);
        assertEq(nft.highestLevel(alice), 5);
    }

    function test_claimNextFeather_blocksReentrancy() public {
        ReentrantClaimer claimer = new ReentrantClaimer(nft);
        token.transfer(address(claimer), 3 ether);

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        claimer.claim();

        assertEq(nft.balanceOf(address(claimer)), 0);
        assertEq(claimer.reentryCount(), 0);
    }

    function test_tokenURI_returnsSvgDataUrl() public {
        token.transfer(alice, 1 ether);

        vm.prank(alice);
        nft.claimNextFeather();

        string memory uri = nft.tokenURI(0);
        assertTrue(bytes(uri).length > 0);
        assertEq(_prefix(uri, 19), "data:image/svg+xml,");
    }

    function test_tokenURI_percentEncodesHashInColors() public {
        token.transfer(alice, 1 ether);

        vm.prank(alice);
        nft.claimNextFeather();

        string memory uri = nft.tokenURI(0);
        assertTrue(_contains(uri, "%23FFA500"));
        assertFalse(_contains(uri, "#FFA500"));
    }

    function test_tokenURI_level10IsLargerThanLevel1() public {
        token.transfer(alice, 10 ether);

        vm.startPrank(alice);
        nft.claimNextFeather();
        vm.stopPrank();

        string memory level1Uri = nft.tokenURI(0);
        string memory level10Uri = nft.tokenURI(9);

        assertTrue(bytes(level10Uri).length > bytes(level1Uri).length);
        assertTrue(_contains(level10Uri, "ellipse"));
    }

    function test_hook_emitsEventsWithoutMinting() public {
        token.transfer(alice, 5 ether);

        vm.prank(poolManager);
        vm.expectEmit(true, false, false, true);
        emit InvestingHook.SwapOccurred(alice, 100, -50);

        vm.expectEmit(true, false, false, true);
        emit InvestingHook.MintTriggered(alice, 5);

        hook.afterSwap(100, -50, 0, 0, 0, 0, 0, 0, abi.encode(alice));

        assertEq(nft.balanceOf(alice), 0);
    }

    function test_hook_skipsEventsWhenHookDataMissing() public {
        vm.recordLogs();
        vm.prank(poolManager);
        hook.afterSwap(100, -50, 0, 0, 0, 0, 0, 0, "");

        assertEq(vm.getRecordedLogs().length, 0);
    }

    function test_hook_decodesPackedAddressHookData() public {
        token.transfer(alice, 2 ether);

        vm.prank(poolManager);
        vm.expectEmit(true, false, false, true);
        emit InvestingHook.SwapOccurred(alice, 1, -1);

        vm.expectEmit(true, false, false, true);
        emit InvestingHook.MintTriggered(alice, 2);

        hook.afterSwap(1, -1, 0, 0, 0, 0, 0, 0, abi.encodePacked(alice));
    }

    function test_constructor_revertsOnZeroAddresses() public {
        vm.expectRevert("Token zero");
        new InvestingNFT(address(0));

        vm.expectRevert("Token zero");
        new InvestingHook(address(0), address(nft));

        vm.expectRevert("NFT zero");
        new InvestingHook(address(token), address(0));
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
