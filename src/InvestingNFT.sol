// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import {InvestingConfig} from "./InvestingConfig.sol";

/**
 * @title Investing NFT
 * @notice ERC721 feather NFTs earned by trading $INVEST on the hooked pool.
 * @dev Level 1 is the full base feather (gold). Higher levels reuse that art with new colors.
 */
contract InvestingNFT is ERC721URIStorage, ERC721Enumerable, ReentrancyGuard {
    uint256 public constant TOKENS_PER_LEVEL = InvestingConfig.TOKENS_PER_LEVEL;
    uint256 public constant MIN_SWAP_VOLUME = InvestingConfig.MIN_SWAP_VOLUME;
    uint256 public constant MAX_CLAIM_PER_TX = InvestingConfig.MAX_CLAIM_PER_TX;

    uint256 private _nextTokenId;

    mapping(uint256 => uint256) public tokenIdToLevel;
    mapping(address => uint256) public highestLevel;
    mapping(address => uint256) public investAccumulated;

    address public immutable deployer;
    address public hook;

    string private constant BASE_GOLD = "#FFD166";

    string[7] private accentPalette = ["#FF6B6B", "#FFA500", "#4ECDC4", "#FF00FF", "#00FFFF", "#800080", "#00FF00"];

    event HookUpdated(address indexed hook);
    event FeatherClaimed(address indexed owner, uint256 indexed tokenId, uint256 level);

    error OnlyHook();
    error OnlyDeployer();
    error HookAlreadySet();
    error HookZero();

    modifier onlyHook() {
        if (msg.sender != hook) revert OnlyHook();
        _;
    }

    constructor() ERC721("Investing", "INVEST") {
        deployer = msg.sender;
    }

    function setHook(address _hook) external {
        if (msg.sender != deployer) revert OnlyDeployer();
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
        if (count > MAX_CLAIM_PER_TX) {
            count = MAX_CLAIM_PER_TX;
        }

        for (uint256 i = 0; i < count; i++) {
            uint256 tokenId = _nextTokenId++;
            uint256 featherLevel = startLevel + i;
            _safeMint(msg.sender, tokenId);
            tokenIdToLevel[tokenId] = featherLevel;
            emit FeatherClaimed(msg.sender, tokenId, featherLevel);
        }

        highestLevel[msg.sender] = startLevel + count - 1;
    }

    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        _requireOwned(tokenId);
        uint256 level = tokenIdToLevel[tokenId];
        string memory color = _featherColor(level);
        string memory svg = _buildFeatherSvg(color, level);
        string memory image = string(abi.encodePacked("data:image/svg+xml;base64,", Base64.encode(bytes(svg))));

        string memory metadata = string(
            abi.encodePacked(
                '{"name":"Investing Feather #',
                _toString(level),
                '","description":"Feather level ',
                _toString(level),
                " earned by trading $INVEST on the hooked Uniswap v4 pool.",
                '","image":"',
                image,
                '","attributes":[',
                _buildAttributes(level, color),
                "]}"
            )
        );

        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(bytes(metadata))));
    }

    function _buildAttributes(uint256 level, string memory color) internal pure returns (string memory) {
        string memory milestone = _milestoneTrait(level);
        return string(
            abi.encodePacked(
                '{"trait_type":"Level","value":',
                _toString(level),
                '},{"trait_type":"Accent","value":"',
                color,
                '"},{"trait_type":"Milestone","value":"',
                milestone,
                '"}'
            )
        );
    }

    function _milestoneTrait(uint256 level) internal pure returns (string memory) {
        if (level == 1) return "First Feather";
        if (level == 10) return "Decade";
        if (level == 25) return "Quarter Century";
        if (level == 50) return "Half Century";
        if (level == 100) return "Century";
        if (level % 10 == 0) return "Deca Tier";
        return "Standard";
    }

    function _featherColor(uint256 level) internal view returns (string memory) {
        if (level == 1) {
            return BASE_GOLD;
        }
        return accentPalette[(level - 2) % accentPalette.length];
    }

    /**
     * @dev Level 1 uses the full ornate base feather. Milestone levels add a glow ring.
     */
    function _buildFeatherSvg(string memory color, uint256 level) internal pure returns (string memory) {
        string memory milestoneGlow = _milestoneGlow(level, color);

        return string(
            abi.encodePacked(
                "<svg xmlns='http://www.w3.org/2000/svg' width='240' height='240' viewBox='0 0 100 100'>",
                "<defs><radialGradient id='bg' cx='50%' cy='50%' r='50%'>",
                "<stop offset='0%' stop-color='#111'/>",
                "<stop offset='100%' stop-color='#000'/>",
                "</radialGradient></defs>",
                "<rect width='100' height='100' fill='url(%23bg)'/>",
                milestoneGlow,
                "<g transform='translate(50,50) scale(1) translate(-46,-50)'>",
                "<path d='M46 97 L45 4 C30 12 21 32 20 50 C19 68 25 82 35 92 C38 95 41 96 46 97 C51 96 54 95 57 92 C67 82 73 68 72 50 C71 32 62 12 47 4 Z' fill='",
                color,
                "'/>",
                "<path d='M46 97 L45.5 4 C34 10 27 26 26 42 C25 58 29 72 36 84 C38 89 41 94 46 97 C51 94 54 89 56 84 C63 72 67 58 66 42 C65 26 58 10 46.5 4 Z' fill='",
                color,
                "' opacity='0.45'/>",
                "<line x1='46' y1='97' x2='45.5' y2='3' stroke='#C9A020' stroke-width='1.3'/>",
                "<rect x='43.5' y='94' width='5.5' height='5' rx='1' fill='#3E2723'/>",
                "<ellipse cx='46' cy='96' rx='2' ry='1.2' fill='#5D4037'/>",
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
                "</g>",
                _levelBadge(level),
                "</svg>"
            )
        );
    }

    function _milestoneGlow(uint256 level, string memory color) internal pure returns (string memory) {
        if (level != 1 && level != 10 && level != 25 && level != 50 && level != 100) {
            return "";
        }

        return string(
            abi.encodePacked(
                "<circle cx='50' cy='50' r='42' fill='none' stroke='", color, "' stroke-width='1.5' opacity='0.35'/>"
            )
        );
    }

    function _levelBadge(uint256 level) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                "<text x='50' y='12' text-anchor='middle' font-size='7' fill='#EEE' font-family='monospace'>L",
                _toString(level),
                "</text>"
            )
        );
    }

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Enumerable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value) internal override(ERC721, ERC721Enumerable) {
        super._increaseBalance(account, value);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721URIStorage, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
