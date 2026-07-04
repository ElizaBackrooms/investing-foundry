# Investing Foundry — Goals

## GOAL 1: Level 1 is the base feather
**Success:** The first feather a user claims is the full ornate golden design (formerly “level 10”). Every level uses that same silhouette; higher levels change color, not size.

## GOAL 2: 1 billion $INVEST supply
**Success:** `InvestingToken` mints exactly 1,000,000,000 tokens at deploy. Progression uses **100,000 tokens per feather level** (level 10 ≈ 1M bought, level 100 ≈ 10M bought).

## GOAL 3: Swap-earned progression (Unipeg-style)
**Success:** Hook records cumulative INVEST bought. Claim never checks wallet balance. Sell your bags, keep your feathers.

## GOAL 4: Safe claiming
**Success:** Hook-only volume recording, reentrancy guard on claim, no auto-mint in hook.

## GOAL 5: Production-ready pipeline
**Success:** Deploy script wires hook ↔ NFT, env vars documented, 16+ tests green.
