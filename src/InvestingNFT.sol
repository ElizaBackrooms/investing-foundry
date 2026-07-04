// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {InvestingConfig} from "./InvestingConfig.sol";

/**
 * @title Investing NFT
 * @notice ERC721 feather NFTs earned by trading $INVEST on the hooked pool.
 * @dev Level 1 is the full base feather (gold). Higher levels reuse that art with new colors.
 */
contract InvestingNFT is ERC721URIStorage, ReentrancyGuard {
    uint256 public constant TOKENS_PER_LEVEL = InvestingConfig.TOKENS_PER_LEVEL;

    uint256 private _nextTokenId;

    mapping(uint256 => uint256) public tokenIdToLevel;
    mapping(address => uint256) public highestLevel;
    mapping(address => uint256) public investAccumulated;

    address public hook;

    string private constant BASE_GOLD = "#FFD166";

    string[7] private accentPalette = [
        "#FF6B6B",
        "#FFA500",
        "#4ECDC4",
        "#FF00FF",
        "#00FFFF",
        "#800080",
        "#00FF00"
    ];

    event HookUpdated(address indexed hook);

    error OnlyHook();
    error HookAlreadySet();
    error HookZero();

    modifier onlyHook() {
        if (msg.sender != hook) revert OnlyHook();
        _;
    }

    constructor() ERC721("Investing", "INVEST") {}

    function setHook(address _hook) external {
        if (hook != address(0)) revert HookAlreadySet();
        if (_hook == address(0)) revert HookZero();
        hook = _hook;
        emit HookUpdated(_hook);
    }

    function recordInvestFromSwap(address user, uint256 amount) external onlyHook {
        if (user == address(0) || amount == 0) {
            return;
        }
        investAccumulated[user] += amount;
    }

    function eligibleLevel(address user) public view returns (uint256) {
        return investAccumulated[user] / TOKENS_PER_LEVEL;
    }

    function claimNextFeather() public nonReentrant {
        uint256 level = eligibleLevel(msg.sender);

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
        string memory svg = _buildFeatherSvg(_featherColor(level));
        return string(abi.encodePacked("data:image/svg+xml,", _urlEncode(svg)));
    }

    function _featherColor(uint256 level) internal view returns (string memory) {
        if (level == 1) {
            return BASE_GOLD;
        }
        return accentPalette[(level - 2) % accentPalette.length];
    }

    /**
     * @dev Level 1 uses the full ornate base feather. All levels share this silhouette.
     */
    function _buildFeatherSvg(string memory color) internal pure returns (string memory) {
        string memory svg = string(
            abi.encodePacked(
                "<svg xmlns='http://www.w3.org/2000/svg' width='240' height='240' viewBox='0 0 100 100'>",
                "<rect width='100' height='100' fill='%23000'/>",
                "<g transform='translate(50,50) scale(1) translate(-46,-50)'>",
                "<path d='M46 97 L45 4 C30 12 21 32 20 50 C19 68 25 82 35 92 C38 95 41 96 46 97 C51 96 54 95 57 92 C67 82 73 68 72 50 C71 32 62 12 47 4 Z' fill='",
                color,
                "'/>",
                "<path d='M46 97 L45.5 4 C34 10 27 26 26 42 C25 58 29 72 36 84 C38 89 41 94 46 97 C51 94 54 89 56 84 C63 72 67 58 66 42 C65 26 58 10 46.5 4 Z' fill='",
                color,
                "' opacity='0.45'/>",
                "<line x1='46' y1='97' x2='45.5' y2='3' stroke='%23C9A020' stroke-width='1.3'/>",
                "<rect x='43.5' y='94' width='5.5' height='5' rx='1' fill='%233E2723'/>",
                "<ellipse cx='46' cy='96' rx='2' ry='1.2' fill='%235D4037'/>",
                "<g stroke='",
                color,
                "' stroke-width='0.3' opacity='0.55'>",
                "<line x1='46' y1='90' x2='24' y2='86'/><line x1='46' y1='90' x2='68' y2='86'/>",
                "<line x1='46' y1='80' x2='22' y2='74'/><line x1='46' y1='80' x2='70' y2='74'/>",
                "<line x1='46' y1='70' x2='21' y2='63'/><line x1='46' y1='70' x2='71' y2='63'/>",
                "<line x1='46' y1='60' x2='20' y2='52'/><line x1='46' y1='60' x2='72' y2='52'/>",
                "<line x1='46' y1='50' x2='21' y2='41'/><line x1='46' y1='50' x2='71' y2='41'/>",
                "<line x1='46' y1='40' x2='23' y2='30'/><line x1='46' y1='40' x2='69' y2='30'/>",
                "<line x1='46' y1='30' x2='26' y2='19'/><line x1='46' y1='30' x2='66' y2='19'/>",
                "<line x1='46' y1='20' x2='30' y2='11'/><line x1='46' y1='20' x2='62' y2='11'/>",
                "<line x1='46' y1='12' x2='35' y2='6'/><line x1='46' y1='12' x2='57' y2='6'/>",
                "<line x1='46' y1='6' x2='42' y2='3'/><line x1='46' y1='6' x2='50' y2='3'/>",
                "</g>",
                "<path d='M46 8 Q44 2 46 0 Q48 2 46 8' fill='",
                color,
                "'/>",
                "</g></svg>"
            )
        );
        return svg;
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
