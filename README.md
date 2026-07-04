# Investing Project - Unipeg-style on Robinhood Chain

## Overview

Investing is a Unipeg-style project on Robinhood Chain where trading the $INVEST token on Uniswap v4 automatically makes users eligible to claim unique on-chain SVG feather NFTs representing their investment level.

**Key Mechanics:**
- Trade $INVEST on Uniswap v4 (with our hook attached)
- Hook emits events on swaps (no risky minting in hook)
- Users call `claimNextFeather()` to mint NFTs based on their current $INVEST balance
- Each NFT represents a "version" of investing (v1, v2, v3...) with unique feather art
- On-chain SVG generation - no IPFS needed

## Contracts

### InvestingToken.sol
- ERC20 token with fixed supply of 10,000 $INVEST
- Simple and secure - no mint/burn beyond initial allocation

### InvestingNFT.sol
- ERC721 token representing "Investing" feather NFTs
- **Claim-based minting**: Users must call `claimNextFeather()` to mint
- Checks real token balance: can only claim level N if holding ≥ N $INVEST
- On-chain SVG feather generation with color/height variations
- Trusts only the verified InvestingToken address (set at deployment)

### InvestingHook.sol
- Uniswap v4 hook that attaches to a pool
- Emits `SwapOccurred` and `MintTriggered` events on swaps
- Does NOT perform minting directly (eliminates exploit vectors)
- Users claim NFTs separately via `claimNextFeather()` on the NFT contract

## Security

This implementation addresses critical vulnerabilities found in early Unipeg-style projects:

✅ **Fixed untrusted token address vulnerability**: NFT contract stores trusted token address at construction
✅ **Removed risky auto-minting from hook**: Hook only emits events, claiming is user-initiated  
✅ **Balance-based claiming**: Users can only claim NFTs up to their actual token balance
✅ **No flash loan exploits**: Fake balance attacks prevented by trusted token address
✅ **Minimal hook permissions**: Hook only needs `afterSwap` access

## Deployment

### Prerequisites
- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Robinhood Chain RPC URL (testnet or mainnet)
- Wallet with funds for gas
- WETH address on target network

### Setup
```bash
# Clone repo
git clone <repo-url>
cd investing-foundry

# Install dependencies
forge install uniswap/v4-core
forge install uniswap/v4-periphery
forge install OpenZeppelin/openzeppelin-contracts

# Copy env template
cp .env.example .env
# Edit .env with your PRIVATE_KEY, RPC_URL, WETH_ADDRESS
```

### Deploy to Testnet (Recommended First)
```bash
source .env

forge script script/DeployInvesting.s.sol:DeployInvesting \
  --rpc-url https://rpc.testnet.chain.robinhood.com \
  --broadcast \
  --verify \
  --verifier blockscout \
  --verifier-url https://explorer.testnet.chain.robinhood.com/api/
```

### Deploy to Mainnet
```bash
source .env

forge script script/DeployInvesting.s.sol:DeployInvesting \
  --rpc-url https://rpc.mainnet.chain.robinhood.com \
  --broadcast \
  --verify \
  --verifier blockscout \
  --verifier-url https://explorer.mainnet.chain.robinhood.com/api/
```

## Usage

1. **Provide liquidity**: Create a Uniswap v4 pool for $INVEST/WETH with our hook attached
2. **Trade**: Swap $INVEST on the pool
3. **Claim**: After trading, call `claimNextFeather()` on the InvestingNFT contract
   - You can claim multiple levels if you've accumulated enough tokens
   - Each claim mints the next version feather NFT

## Development

### Testing
```bash
forge test
```

### Formatting
```bash
forge fmt
```

### Gas Snapshots
```bash
forge snapshot
```

## Architecture

```
User → [Uniswap v4 Pool (with InvestingHook)] 
                     ↓ (swap events)
InvestingHook → emits SwapOccurred + MintTriggered events
                     ↓ (calls NFT contract)
InvestingNFT → claimNextFeather() → checks balance → mints if eligible
                     ↓
User receives Investing Feather NFT (on-chain SVG)
```

## Future Enhancements

- [ ] Add trait system (feather type, size, glow effects) with rarity scoring
- [ ] Implement cooldown between claims to slow progression
- [ ] Create simple frontend to view your NFT collection
- [ ] Add batch claiming for multiple pending levels
- [ ] Integrate with Robinhood Chain's NFT standards
- [ ] Add metadata URI options for off-chain art variations

## Security Notes

- Always use `claimNextFeather()` to mint NFTs based on your token balance
- The hook is intentionally minimal - it only emits events and calls the trusted NFT contract
- All financial logic (balance checking) resides in the NFT contract
- Contracts use OpenZeppelin's battle-tested libraries
- Consider a formal audit before deploying significant liquidity

## License

MIT