# $INVEST Tokenomics

## Supply

| Parameter | Value |
|-----------|-------|
| Total supply | **1,000,000,000** $INVEST |
| Minting | Fixed at deploy (no further mint) |
| Burns | Disabled |

## Feather progression

Progression is **swap-earned**, not balance-held:

1. User buys $INVEST on the hooked Uniswap v4 pool.
2. `InvestingHook` records cumulative INVEST purchased per wallet.
3. User calls `claimNextFeather()` on `InvestingNFT` to mint all pending levels.
4. Selling tokens after earning volume does **not** remove eligibility.

| Parameter | Value |
|-----------|-------|
| Tokens per level | **100,000** $INVEST bought |
| Level 1 | 100k cumulative buys |
| Level 10 | 1M cumulative buys |
| Level 100 | 10M cumulative buys |
| Min swap to count | **1,000** $INVEST per swap (anti-wash) |

## NFTs

- **Standard ERC721** — feathers are tradable on any marketplace.
- **On-chain metadata** — JSON + SVG, no IPFS required.
- **Level 1 art** — full ornate gold base feather; higher levels reuse silhouette with new accent colors.
- **Milestones** — levels 1, 10, 25, 50, and 100 include special milestone traits and glow.

## Protocol fees

The hook does not take swap fees. Any pool LP fee is set at pool creation (default script: 0.30%).

## Security model

- Only the verified hook address may record swap volume.
- Hook permission: `afterSwap` only (minimal attack surface).
- Claiming uses `nonReentrant` and never checks wallet balance at claim time.
- Hook address must be mined with `AFTER_SWAP_FLAG` via CREATE2.

## Deployment checklist

1. Deploy `InvestingToken`, `InvestingNFT`, mined `InvestingHook`, and `PoolManager` (or use existing).
2. `setHook()` on the NFT (one-time).
3. Initialize INVEST/WETH pool with hook via `DeployPool.s.sol`.
4. Add liquidity and publish contract addresses to the frontend config.
