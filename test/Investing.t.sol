// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/InvestingToken.sol";
import "../src/InvestingNFT.sol";
import "../src/InvestingHook.sol";

contract InvestingTest is Test {
    InvestingToken internal token;
    InvestingNFT internal nft;
    InvestingHook internal hook;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

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

    function test_tokenURI_returnsSvgDataUrl() public {
        token.transfer(alice, 1 ether);

        vm.prank(alice);
        nft.claimNextFeather();

        string memory uri = nft.tokenURI(0);
        assertTrue(bytes(uri).length > 0);
        assertEq(_prefix(uri, 19), "data:image/svg+xml,");
    }

    function test_hook_emitsEventsWithoutMinting() public {
        token.transfer(alice, 5 ether);

        vm.expectEmit(true, false, false, true);
        emit InvestingHook.SwapOccurred(address(this), 100, -50);

        vm.expectEmit(true, false, false, true);
        emit InvestingHook.MintTriggered(alice, 5);

        hook.afterSwap(100, -50, 0, 0, 0, 0, 0, 0, abi.encode(alice));

        assertEq(nft.balanceOf(alice), 0);
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
}
