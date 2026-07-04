# Investing Foundry — Goals

## GOAL 1: Level 1 is the base feather ✅
**Success:** The first feather a user claims is the full ornate golden design (formerly “level 10”). Every level uses that same silhouette; higher levels change color, not size.

**Status:** Complete — `InvestingNFT._buildFeatherSvg` uses the full base silhouette at level 1 with gold accent; higher levels cycle accent palette only.

## GOAL 2: 1 billion $INVEST supply ✅
**Success:** `InvestingToken` mints exactly 1,000,000,000 tokens at deploy. Progression uses **100,000 tokens per feather level** (level 10 ≈ 1M bought, level 100 ≈ 10M bought).

**Status:** Complete — `InvestingConfig.MAX_SUPPLY` and `TOKENS_PER_LEVEL` enforced in token and NFT contracts.

## GOAL 3: Swap-earned progression (Unipeg-style) ✅
**Success:** Hook records cumulative INVEST bought. Claim never checks wallet balance. Sell your bags, keep your feathers.

**Status:** Complete — `InvestingHook` records positive INVEST delta; `claimNextFeather` uses `investAccumulated` only. Covered by `test_claimNextFeather_worksAfterSellingTokens`.

## GOAL 4: Safe claiming ✅
**Success:** Hook-only volume recording, reentrancy guard on claim, no auto-mint in hook, 1k min swap anti-wash.

**Status:** Complete — `onlyHook`, `nonReentrant`, `MIN_SWAP_VOLUME`, no mint in hook. 28 tests green.

## GOAL 5: Production-ready pipeline ✅
**Success:** Real v4 `IHooks` hook with CREATE2 mining, pool init script, JSON metadata, claim frontend, 21+ tests green, TOKENOMICS.md published.

**Status:** Complete — `DeployInvesting.s.sol`, `DeployPool.s.sol`, `AddLiquidity.s.sol`, `LAUNCH.md`, `frontend/`, `TOKENOMICS.md`, 28 tests, `InvestingSwapRouter`, deployment manifest.

## GOAL 6: Launch readiness checklist

Pre-mainnet gate. All items should be checked before public launch.

### Contracts & deploy
- [ ] `forge test` — 28/28 passing on release commit
- [ ] Deploy to target network via `DeployInvesting.s.sol`
- [ ] `setHook()` called once with mined hook address
- [ ] Pool initialized via `DeployPool.s.sol` with correct INVEST/WETH + hook
- [ ] Contracts verified on block explorer
- [ ] `deployments/latest.json` committed or published for frontend

### Security & config
- [ ] Hook address matches CREATE2 mined `AFTER_SWAP_FLAG` address
- [ ] NFT `hook` immutably set; deployer key secured
- [ ] `InvestingSwapRouter` address published as canonical swap entrypoint
- [ ] Spot-check: generic router without `hookData` does not credit volume
- [ ] Spot-check: sells do not increment `investAccumulated`
- [ ] Spot-check: swaps &lt; 1k INVEST do not record volume

### Liquidity & tokenomics
- [ ] LP seeded per [docs/TOKENOMICS_EXECUTION.md](docs/TOKENOMICS_EXECUTION.md)
- [ ] Treasury / team allocations moved off hot deployer wallet
- [ ] Initial price and FDV documented publicly

### Frontend & ops
- [ ] `frontend/config.json` populated from deployment manifest
- [ ] Buy flow tested end-to-end on target network
- [ ] Claim flow tested (`claimNextFeather` + metadata renders)
- [ ] RPC and explorer URLs documented in [LAUNCH.md](LAUNCH.md)

### Indexing & analytics
- [ ] Indexer spec reviewed: [docs/INDEXER.md](docs/INDEXER.md)
- [ ] `InvestRecorded` and `FeatherClaimed` events visible on explorer
- [ ] Leaderboard or volume UI wired (optional at launch)

### Documentation
- [ ] [README.md](README.md) links to docs and launch guide
- [ ] [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) reviewed by team
- [ ] [TOKENOMICS.md](TOKENOMICS.md) matches deployed constants

### Communications
- [ ] Router address and “use official router” messaging live
- [ ] Level / volume rules (100k per level, 1k min swap) published
- [ ] Support channel ready for stuck claims / wrong router usage
