// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import {IInvestingToken} from "./interfaces/IInvestingToken.sol";

/**
 * @title Investing NFT
 * @notice ERC721 token for the Investing project on Robinhood Chain.
 * @dev On-chain SVG feathers derived from the level-10 base silhouette.
 */
contract InvestingNFT is ERC721URIStorage, ReentrancyGuard {
    using Strings for uint256;

    uint256 private constant BASE_LEVEL = 10;
    uint256 private constant MIN_SCALE_BPS = 4000; // level 1 ~= 40% of base
    uint256 private constant MAX_SCALE_BPS = 10000; // level 10 = full base size

    uint256 private _nextTokenId;

    mapping(uint256 => uint256) public tokenIdToLevel;
    mapping(address => uint256) public highestLevel;

    string[8] private palette = [
        "#FF6B6B", // Red-coral
        "#FFA500", // Orange
        "#4ECDC4", // Teal
        "#FFD166", // Gold
        "#FF00FF", // Magenta
        "#00FFFF", // Cyan
        "#800080", // Purple
        "#00FF00" // Green
    ];

    address public immutable investingToken;

    constructor(address _investingToken) ERC721("Investing", "INVEST") {
        require(_investingToken != address(0), "Token zero");
        investingToken = _investingToken;
    }

    function claimNextFeather() public nonReentrant {
        uint256 balance = IInvestingToken(investingToken).balanceOf(msg.sender);
        uint256 level = balance / 1e18;

        if (level <= highestLevel[msg.sender]) {
            return;
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

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        uint256 level = tokenIdToLevel[tokenId];
        string memory color = palette[level % palette.length];
        string memory svg = _buildFeatherSvg(level, color);
        return string(abi.encodePacked("data:image/svg+xml,", _urlEncode(svg)));
    }

    /**
     * @dev Level 10 is the canonical base feather. Lower levels use the same
     *      silhouette scaled down with fewer barb details.
     */
    function _buildFeatherSvg(uint256 level, string memory color) internal pure returns (string memory) {
        uint256 tier = level > BASE_LEVEL ? BASE_LEVEL : (level == 0 ? 1 : level);
        uint256 scaleBps = MIN_SCALE_BPS + ((tier - 1) * (MAX_SCALE_BPS - MIN_SCALE_BPS)) / (BASE_LEVEL - 1);
        string memory scale = _formatScale(scaleBps);
        uint256 barbRows = tier >= 8 ? 10 : (tier >= 5 ? 6 : (tier >= 3 ? 3 : 0));

        string memory svg = string(
            abi.encodePacked(
                "<svg xmlns='http://www.w3.org/2000/svg' width='240' height='240' viewBox='0 0 100 100'>",
                "<rect width='100' height='100' fill='%23000'/>",
                "<g transform='translate(50,50) scale(",
                scale,
                ") translate(-46,-50)'>",
                "<path d='M46 97 L45 4 C30 12 21 32 20 50 C19 68 25 82 35 92 C38 95 41 96 46 97 C51 96 54 95 57 92 C67 82 73 68 72 50 C71 32 62 12 47 4 Z' fill='",
                color,
                "'/>"
            )
        );

        if (tier >= 5) {
            svg = string(
                abi.encodePacked(
                    svg,
                    "<path d='M46 97 L45.5 4 C34 10 27 26 26 42 C25 58 29 72 36 84 C38 89 41 94 46 97 C51 94 54 89 56 84 C63 72 67 58 66 42 C65 26 58 10 46.5 4 Z' fill='",
                    color,
                    "' opacity='0.45'/>"
                )
            );
        }

        svg = string(
            abi.encodePacked(
                svg,
                "<line x1='46' y1='97' x2='45.5' y2='3' stroke='%233E2723' stroke-width='1.2'/>"
            )
        );

        if (tier >= 3) {
            svg = string(
                abi.encodePacked(
                    svg,
                    "<rect x='43.5' y='94' width='5.5' height='5' rx='1' fill='%233E2723'/>"
                )
            );
        }

        if (barbRows > 0) {
            svg = string(abi.encodePacked(svg, "<g stroke='", color, "' stroke-width='0.35' opacity='0.5'>"));
            svg = string(abi.encodePacked(svg, _barbRows(barbRows)));
            svg = string(abi.encodePacked(svg, "</g>"));
        }

        if (tier >= BASE_LEVEL) {
            svg = string(
                abi.encodePacked(
                    svg,
                    "<ellipse cx='46' cy='96' rx='2' ry='1.2' fill='%235D4037'/>",
                    "<path d='M46 8 Q44 2 46 0 Q48 2 46 8' fill='",
                    color,
                    "'/>"
                )
            );
        }

        svg = string(abi.encodePacked(svg, "</g></svg>"));
        return svg;
    }

    function _barbRows(uint256 rows) internal pure returns (string memory) {
        if (rows >= 10) {
            return string(
                abi.encodePacked(
                    "<line x1='46' y1='90' x2='24' y2='86'/><line x1='46' y1='90' x2='68' y2='86'/>",
                    "<line x1='46' y1='80' x2='22' y2='74'/><line x1='46' y1='80' x2='70' y2='74'/>",
                    "<line x1='46' y1='70' x2='21' y2='63'/><line x1='46' y1='70' x2='71' y2='63'/>",
                    "<line x1='46' y1='60' x2='20' y2='52'/><line x1='46' y1='60' x2='72' y2='52'/>",
                    "<line x1='46' y1='50' x2='21' y2='41'/><line x1='46' y1='50' x2='71' y2='41'/>",
                    "<line x1='46' y1='40' x2='23' y2='30'/><line x1='46' y1='40' x2='69' y2='30'/>",
                    "<line x1='46' y1='30' x2='26' y2='19'/><line x1='46' y1='30' x2='66' y2='19'/>",
                    "<line x1='46' y1='20' x2='30' y2='11'/><line x1='46' y1='20' x2='62' y2='11'/>",
                    "<line x1='46' y1='12' x2='35' y2='6'/><line x1='46' y1='12' x2='57' y2='6'/>",
                    "<line x1='46' y1='6' x2='42' y2='3'/><line x1='46' y1='6' x2='50' y2='3'/>"
                )
            );
        }
        if (rows >= 6) {
            return string(
                abi.encodePacked(
                    "<line x1='46' y1='88' x2='28' y2='84'/><line x1='46' y1='88' x2='64' y2='84'/>",
                    "<line x1='46' y1='74' x2='26' y2='68'/><line x1='46' y1='74' x2='66' y2='68'/>",
                    "<line x1='46' y1='60' x2='24' y2='52'/><line x1='46' y1='60' x2='68' y2='52'/>",
                    "<line x1='46' y1='46' x2='25' y2='37'/><line x1='46' y1='46' x2='67' y2='37'/>",
                    "<line x1='46' y1='32' x2='28' y2='22'/><line x1='46' y1='32' x2='64' y2='22'/>",
                    "<line x1='46' y1='18' x2='34' y2='12'/><line x1='46' y1='18' x2='58' y2='12'/>"
                )
            );
        }
        return string(
            abi.encodePacked(
                "<line x1='46' y1='80' x2='32' y2='76'/><line x1='46' y1='80' x2='60' y2='76'/>",
                "<line x1='46' y1='60' x2='30' y2='54'/><line x1='46' y1='60' x2='62' y2='54'/>",
                "<line x1='46' y1='40' x2='32' y2='32'/><line x1='46' y1='40' x2='60' y2='32'/>"
            )
        );
    }

    function _formatScale(uint256 scaleBps) internal pure returns (string memory) {
        if (scaleBps >= 10000) {
            return "1";
        }
        uint256 whole = scaleBps / 1000;
        uint256 frac = (scaleBps % 1000) / 100;
        if (frac == 0) {
            return string(abi.encodePacked("0.", Strings.toString(whole)));
        }
        return string(abi.encodePacked("0.", Strings.toString(whole), Strings.toString(frac)));
    }

    function _urlEncode(string memory str) internal pure returns (string memory) {
        bytes memory b = bytes(str);
        bytes memory encoded = new bytes(b.length * 3);
        uint256 pos;

        for (uint256 i = 0; i < b.length; i++) {
            if (b[i] == 0x20) {
                encoded[pos++] = 0x25;
                encoded[pos++] = 0x32;
                encoded[pos++] = 0x30;
            } else if (b[i] == 0x3C) {
                encoded[pos++] = 0x25;
                encoded[pos++] = 0x33;
                encoded[pos++] = 0x43;
            } else if (b[i] == 0x3E) {
                encoded[pos++] = 0x25;
                encoded[pos++] = 0x33;
                encoded[pos++] = 0x45;
            } else if (b[i] == 0x23) {
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
