# Investing Launch Plan

Execution roadmap for taking Investing from merge-ready contracts to a live testnet/mainnet launch.

## Phase 1 — Ship launch toolkit (this PR)

| Workstream | Deliverable | Status |
|------------|-------------|--------|
| Deploy scripts | `AddLiquidity.s.sol`, pool metadata in `latest.json` | Done |
| Runbook | `LAUNCH.md` step-by-step deploy + verify + smoke test | Done |
| Network templates | `deployments/robinhood-{testnet,mainnet}.json` | Done |
| Router | `sellInvestForWeth()` + integration tests | Done |
| Tests | Fuzz buy volume (`InvestingFuzz.t.sol`), 28/28 green | Done |
| Frontend | Robinhood chain add, network switch, auto-claim loop, max WETH | Done |
| Docs | `docs/ARCHITECTURE.md`, `docs/INDEXER.md`, `docs/TOKENOMICS_EXECUTION.md` | Done |
| Goals | GOAL 6 launch checklist in `GOALS.md` | Done |

## Phase 2 — Testnet deploy

1. Configure `.env` with testnet RPC, `WETH_ADDRESS`, deployer key
2. `forge script script/DeployInvesting.s.sol` — broadcast + Blockscout verify
3. `forge script script/DeployPool.s.sol` — initialize INVEST/WETH pool
4. `forge script script/AddLiquidity.s.sol` — seed liquidity for swaps
5. Copy `deployments/latest.json` → `frontend/config.testnet.json`
6. Host frontend (static server or IPFS)
7. Smoke test: connect wallet → buy INVEST → claim feather → verify metadata on explorer

## Phase 3 — Hardening before mainnet

- Fork tests against live Robinhood PoolManager + WETH addresses
- External audit on hook, NFT claim path, and router settlement
- Indexer/subgraph from `docs/INDEXER.md` (`InvestRecorded`, `FeatherClaimed`, `SwapOccurred`)
- Treasury/LP allocation per `docs/TOKENOMICS_EXECUTION.md`
- Art upgrade: align on-chain SVG with `images/` PNG references (optional cosmetic)

## Phase 4 — Mainnet launch

- Repeat Phase 2 on mainnet RPC (`chainId` 4663)
- Publish router address and “official router only” messaging
- Monitor first 24h: volume attribution, claim gas, stuck txs

## Success criteria

- Users can buy INVEST via `InvestingSwapRouter.buyInvestWithWeth` and earn volume
- Sells via `sellInvestForWeth` do not inflate feather levels
- `claimNextFeather()` mints JSON+SVG NFTs up to 20 levels per tx
- Frontend works on Robinhood testnet and mainnet without manual ABI edits

See [LAUNCH.md](LAUNCH.md) for commands and env vars.
