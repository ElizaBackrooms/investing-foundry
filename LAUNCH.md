# Investing Launch Runbook

Step-by-step guide to deploy Investing on Robinhood Chain testnet or mainnet, seed the INVEST/WETH Uniswap v4 pool, verify contracts, wire the frontend, and smoke-test the full swap → claim flow.

---

## Overview

| Step | Script / action | Output |
|------|-----------------|--------|
| 1 | Prerequisites & `.env` | Wallet funded, WETH address known |
| 2 | `DeployInvesting.s.sol` | Token, NFT, hook, router, `deployments/latest.json` |
| 3 | `DeployPool.s.sol` | Initialized INVEST/WETH v4 pool |
| 4 | `AddLiquidity.s.sol` | Pool liquidity for swaps |
| 5 | Blockscout verification | Source code public on explorer |
| 6 | Copy manifest to frontend | `frontend/config.json` |
| 7 | Smoke test | Buy INVEST, claim feather |

**Always deploy and validate on testnet before mainnet.**

---

## Prerequisites

### Tooling

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (`forge`, `cast`)
- Git clone of this repo with submodules:

```bash
git clone https://github.com/ElizaBackrooms/investing-foundry
cd investing-foundry
forge install
```

### Network reference

| | Testnet | Mainnet |
|---|---------|---------|
| Chain ID | `46630` | `4663` |
| RPC | `https://rpc.testnet.chain.robinhood.com` | `https://rpc.mainnet.chain.robinhood.com` |
| Explorer | `https://explorer.testnet.chain.robinhood.com` | `https://robinhoodchain.blockscout.com` |
| Verifier API | `https://explorer.testnet.chain.robinhood.com/api/` | `https://robinhoodchain.blockscout.com/api/` |

Templates with zero addresses live in:

- `deployments/robinhood-testnet.json`
- `deployments/robinhood-mainnet.json`

### Wallet & funds

- Deployer EOA with enough **ETH** for gas (hook mining + several contract deploys + pool init + liquidity)
- **WETH** on the target network (wrap native ETH if needed)
- **INVEST** tokens on the deployer wallet for seeding liquidity (full 1B supply mints to deployer at token deploy)

### Optional: existing PoolManager

Robinhood may ship a canonical v4 `PoolManager`. If so, set `POOL_MANAGER` in `.env` and `DeployInvesting` will wire to it instead of deploying a new one.

---

## Environment setup

```bash
cp .env.example .env
```

Edit `.env`:

```bash
# Required
PRIVATE_KEY=0x<deployer_private_key>
RPC_URL=https://rpc.testnet.chain.robinhood.com   # or mainnet RPC
WETH_ADDRESS=0x<weth_on_target_chain>

# Optional — reuse canonical v4 PoolManager
# POOL_MANAGER=0x...

# Pool defaults (must match across DeployInvesting, DeployPool, AddLiquidity)
POOL_FEE=3000
TICK_SPACING=60

# Pool initialization (DeployPool)
# INIT_TICK=0

# Initial liquidity (AddLiquidity) — pick ONE strategy below
# LIQUIDITY_AMOUNT=1000000          # same INVEST + WETH amount (wei)
# LIQUIDITY_INVEST=500000000000000000000000
# LIQUIDITY_WETH=500000000000000000000000
# LIQUIDITY_DELTA=1000000000000000000000000   # raw liquidity units
TICK_LOWER=-120
TICK_UPPER=120

# Optional — reuse a previously deployed PoolModifyLiquidityTest router
# MODIFY_LIQUIDITY_ROUTER=0x...

# Blockscout verification (optional but recommended)
BLOCKSCOUT_API_KEY=
```

Load env (bash):

```bash
set -a && source .env && set +a
```

PowerShell:

```powershell
Get-Content .env | ForEach-Object {
  if ($_ -match '^\s*([^#][^=]+)=(.*)$') { Set-Item -Path "env:$($matches[1].Trim())" -Value $matches[2].Trim() }
}
```

---

## Step 1 — Deploy core contracts

`DeployInvesting.s.sol` deploys:

- `InvestingToken` (1B supply to deployer)
- `InvestingNFT`
- `PoolManager` (unless `POOL_MANAGER` is set)
- `InvestingHook` (CREATE2 + `HookMiner`, `AFTER_SWAP` flag)
- `InvestingSwapRouter`

Writes **`deployments/latest.json`** with all addresses and pool key metadata (`currency0`, `currency1`, `poolFee`, `tickSpacing`, `investIsToken0`, `hookSalt`).

### Testnet

```bash
forge script script/DeployInvesting.s.sol:DeployInvesting \
  --rpc-url "$RPC_URL" \
  --broadcast \
  --verify \
  --verifier blockscout \
  --verifier-url https://explorer.testnet.chain.robinhood.com/api/ \
  -vvvv
```

### Mainnet

```bash
forge script script/DeployInvesting.s.sol:DeployInvesting \
  --rpc-url https://rpc.mainnet.chain.robinhood.com \
  --broadcast \
  --verify \
  --verifier blockscout \
  --verifier-url https://robinhoodchain.blockscout.com/api/ \
  -vvvv
```

### Record addresses

```bash
cat deployments/latest.json
```

Export for the next steps:

```bash
export POOL_MANAGER=$(jq -r .poolManager deployments/latest.json)
export HOOK_ADDRESS=$(jq -r .hook deployments/latest.json)
export INVEST_TOKEN=$(jq -r .investToken deployments/latest.json)
export WETH_ADDRESS=$(jq -r .weth deployments/latest.json)
```

(`jq` optional — copy values manually from the JSON file.)

---

## Step 2 — Initialize the INVEST/WETH pool

`DeployPool.s.sol` calls `PoolManager.initialize` at tick `0` by default (`INIT_TICK` env to override). Starting price is **1:1** in tick space (not necessarily 1:1 USD).

**Requires:** `POOL_MANAGER`, `HOOK_ADDRESS`, `INVEST_TOKEN`, `WETH_ADDRESS`  
**Optional:** `POOL_FEE`, `TICK_SPACING`, `INIT_TICK`

After broadcast, the script **appends** to `deployments/latest.json` (if it exists):

| Field | Meaning |
|-------|---------|
| `poolInitialized` | `true` |
| `initializeTick` | Starting tick |
| `initializeSqrtPriceX96` | Starting sqrt price |
| `poolId` | v4 pool id (bytes32) |

```bash
forge script script/DeployPool.s.sol:DeployPool \
  --rpc-url "$RPC_URL" \
  --broadcast \
  -vvvv
```

**Note:** Pool initialization is a separate tx from contract deploy. Do not skip this step — swaps will fail without an initialized pool.

---

## Step 3 — Add initial liquidity

`AddLiquidity.s.sol` uses Uniswap v4's `PoolModifyLiquidityTest` helper (same pattern as `lib/v4-core/test/utils/Deployers.sol` and `test/InvestingHookIntegration.t.sol`):

1. Builds the pool key from env addresses
2. Deploys `PoolModifyLiquidityTest` (unless `MODIFY_LIQUIDITY_ROUTER` is set)
3. Approves `currency0` and `currency1` to the router
4. Calls `modifyLiquidity`

### Liquidity amount options

Set **one** of:

| Env var(s) | Behavior |
|------------|----------|
| `LIQUIDITY_DELTA` | Use raw liquidity units directly |
| `LIQUIDITY_INVEST` + `LIQUIDITY_WETH` | Compute liquidity from token amounts (wei) via `LiquidityAmounts` |
| `LIQUIDITY_AMOUNT` | Same wei amount for both tokens (1:1 deposit at current price) |

Default tick range: `TICK_LOWER=-120`, `TICK_UPPER=120` (aligned with integration tests).

Ensure the deployer holds enough INVEST and WETH and has approved spending (the script approves max to the router).

```bash
export LIQUIDITY_AMOUNT=1000000000000000000000000   # example: 1M tokens each side

forge script script/AddLiquidity.s.sol:AddLiquidity \
  --rpc-url "$RPC_URL" \
  --broadcast \
  -vvvv
```

Appends to `deployments/latest.json`:

| Field | Meaning |
|-------|---------|
| `liquidityAdded` | `true` |
| `liquidityTickLower` / `liquidityTickUpper` | Position range |
| `liquidityDelta` | Liquidity units added |
| `modifyLiquidityRouter` | Router used (save for future LP changes) |

---

## Step 4 — Verify on Blockscout

If `--verify` was not used during deploy, verify manually:

```bash
# Example: InvestingToken
forge verify-contract <INVEST_TOKEN_ADDRESS> \
  src/InvestingToken.sol:InvestingToken \
  --chain-id 46630 \
  --rpc-url "$RPC_URL" \
  --verifier blockscout \
  --verifier-url https://explorer.testnet.chain.robinhood.com/api/

# InvestingHook — constructor args required
forge verify-contract <HOOK_ADDRESS> \
  src/InvestingHook.sol:InvestingHook \
  --chain-id 46630 \
  --rpc-url "$RPC_URL" \
  --verifier blockscout \
  --verifier-url https://explorer.testnet.chain.robinhood.com/api/ \
  --constructor-args $(cast abi-encode "constructor(address,address,address,address)" \
    "$POOL_MANAGER" "<NFT_ADDRESS>" "$INVEST_TOKEN" "$WETH_ADDRESS")
```

Repeat for `InvestingNFT`, `InvestingSwapRouter`, and `PoolManager` (if you deployed one).

**Hook verification tip:** The hook is deployed with CREATE2 + salt from `hookSalt` in `latest.json`. Use the broadcast artifact or `forge verify-contract` with `--constructor-args` as above.

Mainnet: swap `--chain-id 4663` and verifier URL to `https://robinhoodchain.blockscout.com/api/`.

---

## Step 5 — Wire the frontend

```bash
cp deployments/latest.json frontend/config.json
```

The frontend (`frontend/app.js`) maps manifest fields automatically:

| `latest.json` | Frontend field |
|---------------|----------------|
| `investNft` | `nftAddress` |
| `swapRouter` | `swapRouterAddress` |
| `investToken` | `investTokenAddress` |
| `weth` | `wethAddress` |
| `hook` | `hookAddress` |
| `currency0`, `currency1`, `poolFee`, `tickSpacing` | Pool key for swaps |

Serve locally:

```bash
cd frontend
python -m http.server 8080
```

Open `http://localhost:8080`, click **Load config.json**, connect wallet on Robinhood Chain (chain ID from manifest).

For production hosting, deploy the `frontend/` folder to any static host and ensure `config.json` is present.

---

## Step 6 — Smoke test checklist

Run on **testnet** before mainnet.

### Wallet setup

- [ ] MetaMask (or Robinhood Wallet) on correct chain (46630 testnet / 4663 mainnet)
- [ ] Wallet has ETH for gas
- [ ] Wallet has WETH (wrap via WETH `deposit()` if needed)

### Config

- [ ] `frontend/config.json` matches `deployments/latest.json`
- [ ] **Load config** succeeds in UI
- [ ] Chain ID in UI matches network

### Pool & contracts

- [ ] `poolInitialized: true` in manifest
- [ ] `liquidityAdded: true` in manifest
- [ ] Hook verified on Blockscout
- [ ] `InvestingNFT.setHook` was called during deploy (only hook can record volume)

### Swap flow

- [ ] WETH balance shows in UI
- [ ] Approve WETH to `InvestingSwapRouter` (UI handles this)
- [ ] **Buy INVEST** tx succeeds on explorer
- [ ] Accumulated volume increases (≥ 1,000 INVEST minimum per swap)

### Claim flow

- [ ] Eligible level ≥ 1 after enough cumulative buys (100,000 INVEST per level)
- [ ] **Claim feather** tx succeeds
- [ ] NFT appears in gallery with on-chain SVG metadata

### Edge cases (optional)

- [ ] Second swap increases accumulated volume
- [ ] Selling INVEST does **not** reduce eligible level (swap-earned progression)
- [ ] Swap via generic router **without** `hookData` does **not** count (use `InvestingSwapRouter`)

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `pool not initialized` in AddLiquidity | Skipped DeployPool | Run `DeployPool.s.sol` |
| `identical tokens` | INVEST and WETH addresses equal | Fix env addresses |
| Swap reverts / no volume | Wrong pool key in frontend | Re-copy `latest.json`; check `currency0`/`currency1` order |
| Volume stays 0 | Swap below 1k INVEST min | Increase swap size |
| Volume stays 0 | Not using `InvestingSwapRouter` | Use project router or pass `abi.encode(trader)` as `hookData` |
| Hook deploy fails / high gas | CREATE2 mining | Normal — `HookMiner` searches for valid address; ensure sufficient gas |
| `deployments/latest.json not found` | DeployInvesting not run or wrong cwd | Run from repo root; check `foundry.toml` fs_permissions |
| Verification fails | Wrong constructor args | Use addresses from `latest.json` |

---

## Mainnet launch checklist

- [ ] Full testnet run completed with smoke tests green
- [ ] Tokenomics reviewed ([TOKENOMICS.md](TOKENOMICS.md))
- [ ] Liquidity plan documented (amounts, tick range, who holds LP position)
- [ ] `deployments/robinhood-mainnet.json` updated with live addresses (for public reference)
- [ ] Frontend `config.json` points to mainnet manifest
- [ ] Explorer links shared for token, hook, NFT, router

---

## Quick reference — full testnet sequence

```bash
cp .env.example .env
# edit .env

set -a && source .env && set +a

forge script script/DeployInvesting.s.sol:DeployInvesting \
  --rpc-url "$RPC_URL" --broadcast --verify \
  --verifier blockscout \
  --verifier-url https://explorer.testnet.chain.robinhood.com/api/

export POOL_MANAGER=$(jq -r .poolManager deployments/latest.json)
export HOOK_ADDRESS=$(jq -r .hook deployments/latest.json)
export INVEST_TOKEN=$(jq -r .investToken deployments/latest.json)
export WETH_ADDRESS=$(jq -r .weth deployments/latest.json)
export LIQUIDITY_AMOUNT=1000000000000000000000000

forge script script/DeployPool.s.sol:DeployPool \
  --rpc-url "$RPC_URL" --broadcast

forge script script/AddLiquidity.s.sol:AddLiquidity \
  --rpc-url "$RPC_URL" --broadcast

cp deployments/latest.json frontend/config.json
cd frontend && python -m http.server 8080
```

---

## Related docs

- [README.md](README.md) — architecture and contract overview
- [TOKENOMICS.md](TOKENOMICS.md) — supply and feather progression
- [deployments/config.example.json](deployments/config.example.json) — minimal manifest shape
