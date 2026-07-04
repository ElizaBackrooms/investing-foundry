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
- On-chain JSON + SVG metadata — no IPFS needed

See [TOKENOMICS.md](TOKENOMICS.md) for full supply and progression details.

**Documentation:** [LAUNCH.md](LAUNCH.md) · [docs/](docs/) ([Architecture](docs/ARCHITECTURE.md), [Indexer spec](docs/INDEXER.md), [Tokenomics execution](docs/TOKENOMICS_EXECUTION.md))

## Contracts

### InvestingToken.sol
- ERC20 token with fixed supply of **1,000,000,000** $INVEST
- Simple and secure - no mint/burn beyond initial allocation

### InvestingNFT.sol
- ERC721 feather NFTs with enumerable gallery support
- **Claim-based minting**: Users must call `claimNextFeather()` to mint
- **Level 1 = base feather**: Full ornate gold design on first claim; higher levels change color only
- **Swap-earned levels**: Hook records cumulative INVEST purchased; claim uses that volume, not wallet balance
- **JSON metadata**: Base64 `application/json` token URIs with level, accent, and milestone traits
- On-chain SVG feather generation from the level-1 base silhouette
- Only the verified hook address may record swap volume

### InvestingHook.sol
- **Real Uniswap v4 `IHooks` implementation** (`afterSwap` only)
- Deployed via CREATE2 + `HookMiner` so the address encodes `AFTER_SWAP_FLAG`
- **Canonical pool only** — ignores swaps from pools that are not INVEST/WETH
- Records INVEST bought per swap (positive swap delta on INVEST side)
- **Router-safe attribution** — generic routers without `hookData` are ignored; use `InvestingSwapRouter`
- **1,000 INVEST minimum** per swap to count (anti-wash)
- Emits `SwapOccurred` and `InvestRecorded` events for indexers/frontends
- Does NOT mint NFTs — claiming is user-initiated

### InvestingSwapRouter.sol
- Production swap router for the INVEST/WETH pool
- **`buyInvestWithWeth`** — buy INVEST with WETH; volume credited to `msg.sender`
- **`sellInvestForWeth`** — sell INVEST for WETH; **sells do not earn feather volume**
- **`swap`** — generic v4 swap on the canonical pool (same `hookData` attribution)
- Automatically passes `abi.encode(msg.sender)` as `hookData` so traders earn volume on buys
- Deployed alongside core contracts via `DeployInvesting.s.sol`

## Security

This implementation addresses critical vulnerabilities found in early Unipeg-style projects:

✅ **Fixed untrusted token address vulnerability**: Only the deployed hook can record swap volume  
✅ **Removed risky auto-minting from hook**: Hook only records volume, claiming is user-initiated  
✅ **Swap-based claiming**: Levels come from cumulative INVEST bought, not balance at claim time  
✅ **No flash loan claim exploits**: Volume is recorded at swap time in the hook  
✅ **Canonical pool validation**: Hook only counts INVEST/WETH pool swaps  
✅ **Router attribution**: Generic routers without hookData are ignored; use `InvestingSwapRouter`  
✅ **Claim gas cap**: Max 20 feathers per `claimNextFeather()` call  
✅ **Deployer-only setHook**: Prevents front-running hook wiring

## Deployment

### Prerequisites
- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Robinhood Chain RPC URL (testnet or mainnet)
- Wallet with funds for gas
- WETH address on target network

### Setup
```bash
git clone https://github.com/ElizaBackrooms/investing-foundry
cd investing-foundry

forge install

cp .env.example .env
# Edit .env with PRIVATE_KEY, RPC_URL, WETH_ADDRESS
```

### Deploy contracts
```bash
source .env

forge script script/DeployInvesting.s.sol:DeployInvesting \
  --rpc-url https://rpc.testnet.chain.robinhood.com \
  --broadcast \
  --verify \
  --verifier blockscout \
  --verifier-url https://explorer.testnet.chain.robinhood.com/api/
```

Set `WETH_ADDRESS` in `.env`. Token sort order (`INVEST` as token0 or token1) is derived automatically from addresses at deploy.

### Initialize pool
```bash
export POOL_MANAGER=0x...
export HOOK_ADDRESS=0x...
export INVEST_TOKEN=0x...
export WETH_ADDRESS=0x...

forge script script/DeployPool.s.sol:DeployPool \
  --rpc-url https://rpc.testnet.chain.robinhood.com \
  --broadcast
```

### Add liquidity
```bash
forge script script/AddLiquidity.s.sol:AddLiquidity \
  --rpc-url https://rpc.testnet.chain.robinhood.com \
  --broadcast
```

Full env vars and verification steps: [LAUNCH.md](LAUNCH.md).

## Usage

1. **Provide liquidity**: Add liquidity to the INVEST/WETH v4 pool (see [docs/TOKENOMICS_EXECUTION.md](docs/TOKENOMICS_EXECUTION.md))
2. **Buy**: Swap via **`InvestingSwapRouter.buyInvestWithWeth`** (or pass `abi.encode(yourAddress)` as swap `hookData`)
3. **Sell** (optional): Use **`InvestingSwapRouter.sellInvestForWeth`** — exits do not affect earned feather levels
4. **Claim**: Call `claimNextFeather()` on the InvestingNFT contract
   - Mints up to **20** pending levels per transaction (call again for more)
   - Sell your tokens anytime — earned levels stay with your wallet

See [LAUNCH.md](LAUNCH.md) for the full pre-launch checklist.

## Frontend

Full swap + claim UI in [`frontend/`](frontend/):

```bash
# After deploy, copy the manifest into the frontend folder
cp deployments/latest.json frontend/config.json

cd frontend
python -m http.server 8080
```

Open `http://localhost:8080`, connect wallet, load config, buy INVEST with WETH via `InvestingSwapRouter`, then claim feathers.

## Development

### Testing
```bash
forge test
```

**28 tests** (24 unit + 3 v4 integration + 1 fuzz): claiming, reentrancy, hook auth, metadata, anti-wash, pool validation, router attribution, sell-after-claim, `buyInvestWithWeth` / `sellInvestForWeth`, and fuzzed buy volume.

### Formatting
```bash
forge fmt
```

## Architecture

```
User → InvestingSwapRouter → PoolManager → INVEST/WETH Pool
                                    ↓ afterSwap (INVEST bought)
                              InvestingHook → recordInvestFromSwap()
                                    ↓ user calls claim
                              InvestingNFT → claimNextFeather() → feather NFTs
```

Full diagram, sequence flows, and security properties: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).  
Indexer / subgraph spec: [docs/INDEXER.md](docs/INDEXER.md).

## License

MIT
