# Investing Project - Unipeg-style on Robinhood Chain

## Overview

Investing is a Unipeg-style project on Robinhood Chain where trading the $INVEST token on Uniswap v4 automatically makes users eligible to claim unique on-chain SVG feather NFTs representing their investment level.

**Key Mechanics:**
- Trade $INVEST on Uniswap v4 (with our hook attached)
- Hook records cumulative INVEST **bought** on each swap
- Your feather level = total INVEST bought ÷ **100,000** tokens per level
- **Level 1** = full gold base feather at **100k** cumulative buys
- **Level 10** = **1M** bought · **Level 100** = **10M** bought (on 1B supply)
- Users call `claimNextFeather()` to mint NFTs — **no token balance required at claim**
- Each NFT represents a "version" of investing (v1, v2, v3...) with unique feather art
- On-chain SVG generation - no IPFS needed

## Contracts

### InvestingToken.sol
- ERC20 token with fixed supply of **1,000,000,000** $INVEST
- Simple and secure - no mint/burn beyond initial allocation

### InvestingNFT.sol
- ERC721 token representing "Investing" feather NFTs
- **Claim-based minting**: Users must call `claimNextFeather()` to mint
- **Level 1 = base feather**: Full ornate gold design on first claim; higher levels change color only
- **Swap-earned levels**: Hook records cumulative INVEST purchased; claim uses that volume, not wallet balance
- On-chain SVG feather generation from the level-1 base silhouette
- Only the verified hook address may record swap volume

### InvestingHook.sol
- Uniswap v4 hook that attaches to a pool
- Records INVEST bought per swap into the NFT contract
- Emits `SwapOccurred` and `InvestRecorded` events for indexers/frontends
- Does NOT mint NFTs — claiming is user-initiated

## Security

This implementation addresses critical vulnerabilities found in early Unipeg-style projects:

✅ **Fixed untrusted token address vulnerability**: Only the deployed hook can record swap volume
✅ **Removed risky auto-minting from hook**: Hook only records volume, claiming is user-initiated  
✅ **Swap-based claiming**: Levels come from cumulative INVEST bought, not balance at claim time
✅ **No flash loan claim exploits**: Volume is recorded at swap time in the hook
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
                     ↓ (swap: INVEST bought)
InvestingHook → recordInvestFromSwap() → investAccumulated[user] += amount
                     ↓ (user calls claim)
InvestingNFT → claimNextFeather() → mints feathers up to eligible level
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