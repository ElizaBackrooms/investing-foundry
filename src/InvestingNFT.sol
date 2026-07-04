// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import {IInvestingToken} from "./interfaces/IInvestingToken.sol";

/**
 * @title Investing NFT
 * @notice ERC721 token for the Investing project on Robinhood Chain.
 * @dev Generates on-chain SVG feather NFTs representing investment levels.
 *      Users claim their next feather based on their token balance.
 */
contract InvestingNFT is ERC721URIStorage, ReentrancyGuard {
    using Strings for uint256;

    uint256 private _nextTokenId;

    // Mapping from tokenId to level
    mapping(uint256 => uint256) public tokenIdToLevel;
    // Mapping from user to highest level claimed
    mapping(address => uint256) public highestLevel;

    // Color palette for feathers
    string[8] private palette = [
        "#FF0000", // Red
        "#00FF00", // Green
        "#0000FF", // Blue
        "#FFFF00", // Yellow
        "#FF00FF", // Magenta
        "#00FFFF", // Cyan
        "#FFA500", // Orange
        "#800080" // Purple
    ];

    // Trusted token address (set at construction)
    address public immutable investingToken;

    /**
     * @dev Constructor sets the trusted InvestingToken address
     * @param _investingToken Address of the InvestingToken contract
     */
    constructor(address _investingToken) ERC721("Investing", "INVEST") {
        require(_investingToken != address(0), "Token zero");
        investingToken = _investingToken;
    }

    /**
     * @dev Allows a user to claim their next feather(s) based on their current token balance.
     *      Computes level = balance / 1e18 and mints any missing levels.
     */
    function claimNextFeather() public nonReentrant {
        uint256 balance = IInvestingToken(investingToken).balanceOf(msg.sender);
        uint256 level = balance / 1e18; // Whole number of tokens

        if (level <= highestLevel[msg.sender]) {
            return; // Already caught up
        }

        uint256 startLevel = highestLevel[msg.sender] + 1;
        uint256 count = level - highestLevel[msg.sender];

        for (uint256 i = 0; i < count; i++) {
            uint256 tokenId = _nextTokenId++;
            _safeMint(msg.sender, tokenId);
            tokenIdToLevel[tokenId] = startLevel + i;
        }

        highestLevel[msg.sender] = level;
    }

    /**
     * @dev Returns the token URI as an SVG data URL
     * @param tokenId The NFT token ID
     * @return SVG data URL string
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        uint256 level = tokenIdToLevel[tokenId];

        // Calculate feather height based on level (100-180px)
        uint256 heightMod = level % 5;
        uint256 height = 100 + heightMod * 20; // 100, 120, 140, 160, 180

        // Select color from palette based on level
        uint256 colorIndex = level % 8;
        string memory color = palette[colorIndex];

        // Calculate Y position for the feather (centered vertically)
        uint256 yPos = 120 - height / 2;

        // Convert numbers to strings for SVG
        string memory yStr = Strings.toString(yPos);
        string memory heightStr = Strings.toString(height);

        // Build SVG string with single quotes to avoid double quote escaping
        string memory svg = string(
            abi.encodePacked(
                "<svg xmlns='http://www.w3.org/2000/svg' width='240' height='240'>",
                "<rect width='240' height='240' fill='#000000'/>",
                "<rect x='110' y='",
                yStr,
                "' width='20' height='",
                heightStr,
                "' fill='",
                color,
                "'/>",
                "<polygon points='120,20 110,",
                yStr,
                ",130,",
                yStr,
                "' fill='",
                color,
                "'/>",
                "</svg>"
            )
        );

        // URL encode the SVG for data URI (replace spaces, <, >)
        string memory encoded = _urlEncode(svg);
        return string(abi.encodePacked("data:image/svg+xml,", encoded));
    }

    /**
     * @dev Simple URL encoder for spaces, <, and > characters
     * @param str String to encode
     * @return URL-encoded string
     */
    function _urlEncode(string memory str) internal pure returns (string memory) {
        bytes memory b = bytes(str);
        bytes memory encoded = new bytes(b.length * 3); // Worst case: each byte becomes 3 bytes (%XX)
        uint256 pos;

        for (uint256 i = 0; i < b.length; i++) {
            if (b[i] == 0x20) {
                // Space
                encoded[pos++] = 0x25;
                encoded[pos++] = 0x32;
                encoded[pos++] = 0x30;
            } else if (b[i] == 0x3C) {
                // <
                encoded[pos++] = 0x25;
                encoded[pos++] = 0x33;
                encoded[pos++] = 0x43;
            } else if (b[i] == 0x3E) {
                // >
                encoded[pos++] = 0x25;
                encoded[pos++] = 0x33;
                encoded[pos++] = 0x45;
            } else if (b[i] == 0x23) {
                // #
                encoded[pos++] = 0x25;
                encoded[pos++] = 0x32;
                encoded[pos++] = 0x33;
            } else {
                encoded[pos++] = b[i];
            }
        }

        bytes memory trimmed = new bytes(pos);
        for (uint256 j = 0; j < pos; j++) {
            trimmed[j] = encoded[j];
        }
        return string(trimmed);
    }
}
