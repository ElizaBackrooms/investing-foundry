# $INVEST Tokenomics — Execution Plan

Practical off-chain planning for deploying **1,000,000,000** $INVEST. This is a launch playbook, not on-chain logic. Adjust numbers for market conditions and legal review.

## Supply recap

| Item | Value |
|------|-------|
| Total supply | 1,000,000,000 INVEST |
| Minting | 100% to deployer at `InvestingToken` deploy |
| Progression constant | 100,000 INVEST bought per feather level |
| Max theoretical levels | 10,000 (if entire supply were bought through the pool) |

On-chain, the deployer wallet holds the full supply until manually distributed.

## Recommended allocation (1B supply)

Starting point for a community launch on Robinhood Chain:

| Bucket | % | Tokens | Purpose |
|--------|---|--------|---------|
| **LP seed** | 40–50% | 400M–500M | INVEST/WETH v4 pool depth |
| **Treasury / ops** | 15–20% | 150M–200M | Grants, listings, infra, emergencies |
| **Community / rewards** | 10–15% | 100M–150M | Contests, LP incentives, partnerships |
| **Team** | 10–15% | 100M–150M | Vested off-chain (see vesting below) |
| **Reserve** | 5–10% | 50M–100M | Unallocated buffer |

**Example (mid scenario):**

| Bucket | Tokens |
|--------|--------|
| LP seed | 450,000,000 |
| Treasury | 175,000,000 |
| Community | 125,000,000 |
| Team | 125,000,000 |
| Reserve | 125,000,000 |
| **Total** | **1,000,000,000** |

## LP seeding strategy

### Goals

- Enough depth for early swaps without extreme slippage on 1k–100k INVEST buys.
- Align initial price with narrative (level 1 = 100k bought ≈ meaningful but reachable).
- Keep majority of supply in LP or treasury, not hot wallets.

### Step-by-step

1. **Choose initial price** — e.g. target $0.001 / INVEST → $1M FDV at 1B supply. Derive WETH pairing from ETH/USD at launch.
2. **Deploy contracts** — `DeployInvesting.s.sol` → `DeployPool.s.sol` with 0.30% fee (default script).
3. **Approve PoolManager** — INVEST and WETH to the v4 position manager / pool init path your script uses.
4. **Seed single-sided or balanced liquidity** around the opening tick:
   - **Balanced (recommended):** e.g. 450M INVEST + matching WETH at init `sqrtPriceX96`.
   - **Narrow range:** Concentrate LP in ±2–5% tick band for capital efficiency; widen after volatility stabilizes.
5. **Verify hook** — Pool must use the mined `InvestingHook` address from `deployments/latest.json`.
6. **Smoke test** — Small `buyInvestWithWeth` via router; confirm `InvestRecorded` on explorer.
7. **Publish router address** — Only `InvestingSwapRouter` auto-credits `msg.sender`; document in frontend config.

### LP sizing reference

Rough INVEST amounts for progression (at any price):

| Milestone | Cumulative buy volume |
|-----------|------------------------|
| Level 1 | 100,000 INVEST |
| Level 10 | 1,000,000 INVEST |
| Level 100 | 10,000,000 INVEST |

If opening LP holds 450M INVEST, ~45 users could theoretically reach level 100 if they bought the entire LP inventory (unrealistic; illustrates scale).

### WETH pairing checklist

- [ ] Confirm `WETH_ADDRESS` on target network in `.env`
- [ ] Deployer holds enough WETH + ETH for gas
- [ ] Token sort order (`investIsToken0`) recorded in deployment manifest
- [ ] LP position NFT or liquidity accounted in treasury spreadsheet

## Treasury execution

### Wallet structure

| Wallet | Hold | Access |
|--------|------|--------|
| **Treasury multisig** | Treasury + reserve + undistributed community | 2-of-3 or 3-of-5 |
| **Ops hot wallet** | Small monthly ops float (&lt;1% supply) | Single signer + limits |
| **LP deployer** | Only during seeding; sweep leftovers to multisig | One-time |

### Suggested treasury uses (175M example)

| Use | Allocation | Notes |
|-----|------------|-------|
| CEX / bridge liquidity | 30–50M | If pursuing external listings |
| Ecosystem grants | 25–40M | Builders, indexers, tooling |
| Marketing / events | 20–30M | Launch campaign, KOL at discretion |
| Audit / bug bounty | 5–15M | Reserve if pre-launch audit planned |
| Runway | 40–60M | 12–18 month operating buffer |

Disburse from multisig with public transparency (monthly report or on-chain labels).

## Team & vesting (off-chain)

Document vesting in a team agreement; no vesting contract in v1.

| Tranche | % of team bucket | Cliff | Vest |
|---------|------------------|-------|------|
| Core | 60% | 6 months | 24 months linear |
| Advisors | 20% | 3 months | 12 months linear |
| Early contributors | 20% | none | 12 months linear |

Team tokens should **not** sit in the LP wallet. Transfer to vesting custodian or timelock before announcing allocations.

## Community distribution ideas

- **Trading competitions** — Leaderboard from indexer (`InvestRecorded` volume); rewards in INVEST or WETH from community bucket.
- **LP incentives** — Optional future fee redirect; not in current hook.
- **Feather galleries** — Highlight level 10 / 25 / 50 / 100 claimers; no token cost.

## Launch day timeline (suggested)

| Time | Action |
|------|--------|
| T-24h | Freeze bytecode; run full `forge test`; publish addresses to testnet dry run |
| T-1h | Deploy mainnet contracts; `setHook`; init pool |
| T0 | Seed LP; verify swap + claim on mainnet |
| T+15m | Update `frontend/config.json`; announce router + pool |
| T+1h | Monitor hook events; indexer catch-up |
| T+24h | Treasury sweep from deployer to multisig |

## Risk controls

- **Deployer key** — Use hardware wallet; revoke unlimited approvals after LP seed.
- **No hidden mint** — Supply fixed; verify `totalSupply()` on explorer.
- **Hook immutability** — Hook address fixed at NFT `setHook`; double-check before call.
- **Rug narrative** — Pre-commit LP lock or burn LP position NFT if policy allows.
- **Wash trading** — 1k min swap is on-chain; communicate that sybil volume is possible at scale.

## Post-launch monitoring

| Metric | Source |
|--------|--------|
| Pool liquidity | v4 position / TVL indexer |
| Cumulative buy volume | `InvestRecorded` / [INDEXER.md](./INDEXER.md) |
| Unique traders | Distinct `user` in hook events |
| Feathers minted | `FeatherClaimed` count |
| Treasury runway | Multisig balance sheet |

## Related docs

- [../TOKENOMICS.md](../TOKENOMICS.md) — on-chain rules and constants
- [ARCHITECTURE.md](./ARCHITECTURE.md) — contract flow
- [../LAUNCH.md](../LAUNCH.md) — launch readiness checklist
