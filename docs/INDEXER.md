# Investing Protocol — Indexer Specification

This document specifies how to index Investing protocol activity from on-chain events. Indexers power leaderboards, portfolio UIs, claim eligibility displays, and analytics dashboards.

## Contracts to watch

| Contract | Role | Events |
|----------|------|--------|
| `InvestingHook` | Records swap volume on canonical INVEST/WETH pool | `SwapOccurred`, `InvestRecorded` |
| `InvestingNFT` | Mints feather NFTs on user claim | `FeatherClaimed` |

Deploy addresses live in `deployments/latest.json` after running `DeployInvesting.s.sol`.

## Event reference

### `SwapOccurred`

Emitted on every attributed swap in the canonical pool, **before** volume filtering.

```solidity
event SwapOccurred(address indexed user, int128 delta0, int128 delta1);
```

| Field | Type | Indexed | Description |
|-------|------|---------|-------------|
| `user` | `address` | yes (topic1) | Trader credited for the swap |
| `delta0` | `int128` | no | Token0 balance delta from swap |
| `delta1` | `int128` | no | Token1 balance delta from swap |

- **Topic0:** `0x050ef0486f279aedcbe4555f4fef127c837507a01e2e22fc061c6aa4af3c434d`
- Use this event for raw swap telemetry. Positive INVEST delta indicates a buy; negative indicates a sell (sells do not update `investAccumulated`).

### `InvestRecorded`

Emitted only when a swap buys **≥ 1,000 INVEST** (`MIN_SWAP_VOLUME`) and volume is written to the NFT contract.

```solidity
event InvestRecorded(address indexed user, uint256 amount, uint256 eligibleLevel);
```

| Field | Type | Indexed | Description |
|-------|------|---------|-------------|
| `user` | `address` | yes (topic1) | Trader whose cumulative volume increased |
| `amount` | `uint256` | no | INVEST bought in this swap (wei, 18 decimals) |
| `eligibleLevel` | `uint256` | no | `investAccumulated[user] / TOKENS_PER_LEVEL` after update |

- **Topic0:** `0x310168fa824865a28b4151ea041650a4669245189b135c2b474d631bab362db0`
- **Primary event for progression indexing.** `eligibleLevel` is the max feather level the user can claim (not yet minted count).

Constants (from `InvestingConfig`):

- `TOKENS_PER_LEVEL` = 100,000 × 10¹⁸ (100k INVEST per level)
- `MIN_SWAP_VOLUME` = 1,000 × 10¹⁸

### `FeatherClaimed`

Emitted when a user mints one or more feathers via `claimNextFeather()`.

```solidity
event FeatherClaimed(address indexed owner, uint256 indexed tokenId, uint256 level);
```

| Field | Type | Indexed | Description |
|-------|------|---------|-------------|
| `owner` | `address` | yes (topic1) | Claimant / NFT recipient |
| `tokenId` | `uint256` | yes (topic2) | Minted ERC-721 token ID |
| `level` | `uint256` | no | Feather level for this token |

- **Topic0:** `0xf4ab874c440482bffb2fccd5826e34cfe4a8c4826c4f1924ce2f1a881708520e`
- Up to **20** `FeatherClaimed` events per transaction (`MAX_CLAIM_PER_TX`).

## Indexing rules

1. **User identity** — Always key users by the `user` / `owner` address from hook/NFT events, not `tx.from` (routers are intermediaries).
2. **Volume source of truth** — Derive `investAccumulated` and `eligibleLevel` from `InvestRecorded`, or reconcile with `InvestingNFT.investAccumulated(user)` via eth_call.
3. **Claims vs eligibility** — `eligibleLevel` from the hook is cumulative buy volume ÷ 100k. `highestLevel` (claimed) requires scanning `FeatherClaimed` or calling `InvestingNFT.highestLevel(user)`.
4. **Pending claims** — `pendingLevels = eligibleLevel - highestLevel` (floor at 0).
5. **Sells** — `SwapOccurred` may fire on sells, but `InvestRecorded` will not. Do not decrement accumulated volume on sells.
6. **Dust swaps** — Swaps below 1k INVEST emit `SwapOccurred` only; ignore for volume totals.
7. **Canonical pool only** — Hook ignores non–INVEST/WETH pools; no events from other pools.

## Example: ethers.js v6 listener

```javascript
import { ethers } from "ethers";

const HOOK_ABI = [
  "event SwapOccurred(address indexed user, int128 delta0, int128 delta1)",
  "event InvestRecorded(address indexed user, uint256 amount, uint256 eligibleLevel)",
];
const NFT_ABI = [
  "event FeatherClaimed(address indexed owner, uint256 indexed tokenId, uint256 level)",
  "function investAccumulated(address) view returns (uint256)",
  "function highestLevel(address) view returns (uint256)",
  "function TOKENS_PER_LEVEL() view returns (uint256)",
];

const provider = new ethers.JsonRpcProvider(process.env.RPC_URL);
const hook = new ethers.Contract(process.env.HOOK_ADDRESS, HOOK_ABI, provider);
const nft = new ethers.Contract(process.env.NFT_ADDRESS, NFT_ABI, provider);

const users = new Map(); // address -> { accumulated, eligible, claimed, swaps[] }

function getUser(addr) {
  if (!users.has(addr)) {
    users.set(addr, { accumulated: 0n, eligible: 0n, claimed: 0n, swaps: [], feathers: [] });
  }
  return users.get(addr);
}

hook.on("InvestRecorded", (user, amount, eligibleLevel, event) => {
  const u = getUser(user);
  u.accumulated += amount;
  u.eligible = eligibleLevel;
  u.swaps.push({
    txHash: event.log.transactionHash,
    block: event.log.blockNumber,
    amount,
    eligibleLevel,
  });
  console.log(`Volume: ${user} +${ethers.formatEther(amount)} INVEST → level ${eligibleLevel}`);
});

hook.on("SwapOccurred", (user, delta0, delta1, event) => {
  // Optional: log all swaps including sells and dust
  console.log(`Swap: ${user} delta0=${delta0} delta1=${delta1} tx=${event.log.transactionHash}`);
});

nft.on("FeatherClaimed", (owner, tokenId, level, event) => {
  const u = getUser(owner);
  u.claimed = u.claimed > level ? u.claimed : level;
  u.feathers.push({ tokenId, level, txHash: event.log.transactionHash });
  console.log(`Claim: ${owner} minted token #${tokenId} at level ${level}`);
});

// Reconcile from chain (startup or periodic)
async function syncUser(address) {
  const [accumulated, claimed, tokensPerLevel] = await Promise.all([
    nft.investAccumulated(address),
    nft.highestLevel(address),
    nft.TOKENS_PER_LEVEL(),
  ]);
  return {
    accumulated,
    eligible: accumulated / tokensPerLevel,
    claimed,
    pending: accumulated / tokensPerLevel - claimed,
  };
}
```

### Historical backfill

Use `eth_getLogs` filtered by contract address and topic0:

```javascript
const investRecordedTopic = hook.interface.getEvent("InvestRecorded").topicHash;
const fromBlock = DEPLOY_BLOCK; // from deployments/latest.json

const logs = await provider.getLogs({
  address: process.env.HOOK_ADDRESS,
  topics: [investRecordedTopic],
  fromBlock,
  toBlock: "latest",
});

for (const log of logs) {
  const parsed = hook.interface.parseLog(log);
  // handle parsed.args.user, amount, eligibleLevel
}
```

## Subgraph schema outline

Below is a portable schema suitable for **The Graph**, **Goldsky**, or **Subsquid**. Adjust manifest/network names per platform.

### GraphQL schema (`schema.graphql`)

```graphql
type User @entity {
  id: Bytes!                    # wallet address
  investAccumulated: BigInt!
  eligibleLevel: BigInt!
  highestClaimedLevel: BigInt!
  pendingLevels: BigInt!
  swapCount: BigInt!
  totalInvestBought: BigInt!    # same as investAccumulated; alias for analytics
  swaps: [Swap!]! @derivedFrom(field: "user")
  featherClaims: [FeatherClaim!]! @derivedFrom(field: "owner")
  firstSwapAt: BigInt
  lastSwapAt: BigInt
  createdAt: BigInt!
  updatedAt: BigInt!
}

type Swap @entity {
  id: Bytes!                    # txHash-logIndex
  user: User!
  amount: BigInt!               # INVEST bought this swap
  eligibleLevelAfter: BigInt!
  delta0: BigInt!
  delta1: BigInt!
  counted: Boolean!             # true if InvestRecorded fired
  blockNumber: BigInt!
  blockTimestamp: BigInt!
  transactionHash: Bytes!
}

type FeatherClaim @entity {
  id: Bytes!                    # txHash-logIndex
  owner: User!
  tokenId: BigInt!
  level: BigInt!
  blockNumber: BigInt!
  blockTimestamp: BigInt!
  transactionHash: Bytes!
}

type ProtocolStats @entity {
  id: ID!                       # "global"
  totalVolume: BigInt!
  totalSwapsCounted: BigInt!
  totalFeathersMinted: BigInt!
  uniqueTraders: BigInt!
}
```

### Mapping logic (pseudocode)

**`InvestingHook` — `SwapOccurred`**

```
swap = new Swap(id)
swap.user = getOrCreateUser(user)
swap.delta0 = delta0
swap.delta1 = delta1
swap.counted = false
swap.blockNumber = block.number
...
save(swap)
```

**`InvestingHook` — `InvestRecorded`**

```
user = getOrCreateUser(user)
user.investAccumulated += amount   # or set from eligibleLevel * TOKENS_PER_LEVEL
user.eligibleLevel = eligibleLevel
user.totalInvestBought += amount
user.swapCount += 1
user.pendingLevels = eligibleLevel - user.highestClaimedLevel
user.updatedAt = block.timestamp
link Swap entity for same tx if SwapOccurred was processed first; set counted = true
update ProtocolStats
```

**`InvestingNFT` — `FeatherClaimed`**

```
claim = new FeatherClaim(id)
claim.owner = getOrCreateUser(owner)
claim.tokenId = tokenId
claim.level = level
user.highestClaimedLevel = max(user.highestClaimedLevel, level)
user.pendingLevels = user.eligibleLevel - user.highestClaimedLevel
ProtocolStats.totalFeathersMinted += 1
```

### Subsquid / Goldsky notes

| Platform | Manifest | Tips |
|----------|----------|------|
| **The Graph** | `subgraph.yaml` with `InvestingHook` + `InvestingNFT` data sources | Use `startBlock` from deploy manifest; ABI from `out/*.json` |
| **Goldsky** | Mirror subgraph or custom SQL pipeline | Same schema; pipe `InvestRecorded` to materialized user table |
| **Subsquid** | `squid.yaml` + TypeORM entities matching schema above | Batch processor: handle hook events first, NFT claims in same processor or separate |

### ABI fragments for manifests

```json
[
  {
    "type": "event",
    "name": "SwapOccurred",
    "inputs": [
      { "name": "user", "type": "address", "indexed": true },
      { "name": "delta0", "type": "int128", "indexed": false },
      { "name": "delta1", "type": "int128", "indexed": false }
    ]
  },
  {
    "type": "event",
    "name": "InvestRecorded",
    "inputs": [
      { "name": "user", "type": "address", "indexed": true },
      { "name": "amount", "type": "uint256", "indexed": false },
      { "name": "eligibleLevel", "type": "uint256", "indexed": false }
    ]
  },
  {
    "type": "event",
    "name": "FeatherClaimed",
    "inputs": [
      { "name": "owner", "type": "address", "indexed": true },
      { "name": "tokenId", "type": "uint256", "indexed": true },
      { "name": "level", "type": "uint256", "indexed": false }
    ]
  }
]
```

## Derived queries (examples)

| Query | Source |
|-------|--------|
| Leaderboard by volume | `User` ordered by `investAccumulated` desc |
| Users with unclaimed feathers | `pendingLevels > 0` |
| Level-100 achievers | `eligibleLevel >= 100` |
| Recent claims gallery | `FeatherClaim` ordered by `blockTimestamp` desc |
| Wash-filtered volume | Sum `Swap.amount` where `counted = true` only |

## Operational checklist

- [ ] Set `startBlock` to hook deploy block (see `deployments/latest.json`)
- [ ] Index both hook and NFT contracts from the same network (Robinhood Chain)
- [ ] Handle reorgs: use platform finality settings or rollback N blocks
- [ ] Expose `TOKENS_PER_LEVEL` (100_000e18) as a constant in the indexer config
- [ ] Periodically spot-check `User.investAccumulated` against on-chain `investAccumulated(address)`
