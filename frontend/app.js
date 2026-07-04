import { BrowserProvider, Contract, formatEther, parseEther } from "https://cdn.jsdelivr.net/npm/ethers@6.13.5/+esm";

const TOKENS_PER_LEVEL = 100_000n * 10n ** 18n;
const MIN_SWAP_VOLUME = 1_000n * 10n ** 18n;
const MAX_CLAIM_PER_TX = 20n;

const NFT_ABI = [
  "function investAccumulated(address) view returns (uint256)",
  "function eligibleLevel(address) view returns (uint256)",
  "function highestLevel(address) view returns (uint256)",
  "function balanceOf(address) view returns (uint256)",
  "function tokenOfOwnerByIndex(address,uint256) view returns (uint256)",
  "function tokenIdToLevel(uint256) view returns (uint256)",
  "function tokenURI(uint256) view returns (string)",
  "function claimNextFeather()",
];

const ERC20_ABI = [
  "function balanceOf(address) view returns (uint256)",
  "function allowance(address,address) view returns (uint256)",
  "function approve(address,uint256) returns (bool)",
  "function decimals() view returns (uint8)",
];

const ROUTER_ABI = [
  "function buyInvestWithWeth((address currency0,address currency1,uint24 fee,int24 tickSpacing,address hooks) key, uint128 wethAmountIn) payable returns (int256 delta)",
];

const CONFIG_KEYS = [
  "chainId",
  "nftAddress",
  "swapRouterAddress",
  "investTokenAddress",
  "wethAddress",
  "hookAddress",
  "currency0",
  "currency1",
  "poolFee",
  "tickSpacing",
];

const els = {
  connectBtn: document.getElementById("connectBtn"),
  loadConfigBtn: document.getElementById("loadConfigBtn"),
  walletStatus: document.getElementById("walletStatus"),
  wethAmount: document.getElementById("wethAmount"),
  wethBalance: document.getElementById("wethBalance"),
  swapBtn: document.getElementById("swapBtn"),
  accumulated: document.getElementById("accumulated"),
  eligible: document.getElementById("eligible"),
  claimed: document.getElementById("claimed"),
  pending: document.getElementById("pending"),
  progressPct: document.getElementById("progressPct"),
  progressFill: document.getElementById("progressFill"),
  progressDetail: document.getElementById("progressDetail"),
  claimBtn: document.getElementById("claimBtn"),
  txStatus: document.getElementById("txStatus"),
  gallery: document.getElementById("gallery"),
  saveConfigBtn: document.getElementById("saveConfigBtn"),
  chainId: document.getElementById("chainId"),
  nftAddress: document.getElementById("nftAddress"),
  swapRouterAddress: document.getElementById("swapRouterAddress"),
  investTokenAddress: document.getElementById("investTokenAddress"),
  wethAddress: document.getElementById("wethAddress"),
  hookAddress: document.getElementById("hookAddress"),
  currency0: document.getElementById("currency0"),
  currency1: document.getElementById("currency1"),
  poolFee: document.getElementById("poolFee"),
  tickSpacing: document.getElementById("tickSpacing"),
};

let provider;
let signer;
let account;
let nft;
let swapRouter;
let weth;

function getConfig() {
  return {
    chainId: els.chainId.value.trim(),
    nftAddress: els.nftAddress.value.trim(),
    swapRouterAddress: els.swapRouterAddress.value.trim(),
    investTokenAddress: els.investTokenAddress.value.trim(),
    wethAddress: els.wethAddress.value.trim(),
    hookAddress: els.hookAddress.value.trim(),
    currency0: els.currency0.value.trim(),
    currency1: els.currency1.value.trim(),
    poolFee: Number(els.poolFee.value || 3000),
    tickSpacing: Number(els.tickSpacing.value || 60),
  };
}

function applyConfig(config) {
  const mapping = {
    chainId: config.chainId,
    nftAddress: config.investNft ?? config.nftAddress,
    swapRouterAddress: config.swapRouter,
    investTokenAddress: config.investToken,
    wethAddress: config.weth,
    hookAddress: config.hook,
    currency0: config.currency0,
    currency1: config.currency1,
    poolFee: config.poolFee,
    tickSpacing: config.tickSpacing,
  };

  for (const [field, value] of Object.entries(mapping)) {
    if (value !== undefined && value !== null && els[field]) {
      els[field].value = String(value);
    }
  }
}

function loadLocalConfig() {
  for (const key of CONFIG_KEYS) {
    const stored = localStorage.getItem(`investing.${key}`);
    if (stored && els[key]) {
      els[key].value = stored;
    }
  }
}

function saveLocalConfig() {
  const config = getConfig();
  for (const key of CONFIG_KEYS) {
    localStorage.setItem(`investing.${key}`, String(config[key]));
  }
  bindContracts();
  els.txStatus.textContent = "Saved contract config locally.";
}

async function loadDeploymentConfig() {
  try {
    const response = await fetch("./config.json", { cache: "no-store" });
    if (!response.ok) {
      throw new Error("config.json not found");
    }
    const config = await response.json();
    applyConfig(config);
    saveLocalConfig();
    els.txStatus.textContent = "Loaded config.json from frontend folder.";
  } catch (error) {
    els.txStatus.textContent = "Copy deployments/latest.json to frontend/config.json after deploy.";
  }
}

function bindContracts() {
  const config = getConfig();
  if (!provider) {
    return;
  }

  nft = config.nftAddress ? new Contract(config.nftAddress, NFT_ABI, signer || provider) : null;
  swapRouter = config.swapRouterAddress
    ? new Contract(config.swapRouterAddress, ROUTER_ABI, signer || provider)
    : null;
  weth = config.wethAddress ? new Contract(config.wethAddress, ERC20_ABI, signer || provider) : null;
}

function formatTokens(value) {
  return `${Number(formatEther(value)).toLocaleString(undefined, { maximumFractionDigits: 4 })} INVEST`;
}

function buildPoolKey(config) {
  return {
    currency0: config.currency0,
    currency1: config.currency1,
    fee: config.poolFee,
    tickSpacing: config.tickSpacing,
    hooks: config.hookAddress,
  };
}

function contractsReady() {
  const config = getConfig();
  return Boolean(
    account &&
      nft &&
      swapRouter &&
      weth &&
      config.currency0 &&
      config.currency1 &&
      config.hookAddress &&
      config.swapRouterAddress
  );
}

async function refresh() {
  if (!account || !nft) {
    return;
  }

  const [accumulated, eligible, claimed, balance] = await Promise.all([
    nft.investAccumulated(account),
    nft.eligibleLevel(account),
    nft.highestLevel(account),
    nft.balanceOf(account),
  ]);

  const pending = eligible > claimed ? eligible - claimed : 0n;
  const claimableNow = pending > MAX_CLAIM_PER_TX ? MAX_CLAIM_PER_TX : pending;
  const intoLevel = accumulated % TOKENS_PER_LEVEL;
  const pct = Number((intoLevel * 10000n) / TOKENS_PER_LEVEL) / 100;

  els.accumulated.textContent = formatTokens(accumulated);
  els.eligible.textContent = String(eligible);
  els.claimed.textContent = String(claimed);
  els.pending.textContent = String(pending);
  els.progressPct.textContent = `${pct.toFixed(2)}%`;
  els.progressFill.style.width = `${pct}%`;
  els.progressDetail.textContent = `${formatTokens(intoLevel)} / ${formatTokens(TOKENS_PER_LEVEL)} toward next level · min swap ${formatTokens(MIN_SWAP_VOLUME)}`;

  els.claimBtn.disabled = pending === 0n;
  els.claimBtn.textContent =
    pending > MAX_CLAIM_PER_TX
      ? `Claim ${claimableNow} Feathers (${pending} pending)`
      : pending > 0n
        ? `Claim ${pending} Feather${pending === 1n ? "" : "s"}`
        : "Claim Feathers (max 20 / tx)";

  if (weth) {
    const wethBal = await weth.balanceOf(account);
    els.wethBalance.textContent = `WETH balance: ${formatEther(wethBal)}`;
  }

  els.swapBtn.disabled = !contractsReady();

  if (balance === 0n) {
    els.gallery.className = "gallery empty-state";
    els.gallery.textContent = "No feathers claimed yet.";
    return;
  }

  els.gallery.className = "gallery";
  els.gallery.innerHTML = "";

  for (let i = 0n; i < balance; i++) {
    const tokenId = await nft.tokenOfOwnerByIndex(account, i);
    const level = await nft.tokenIdToLevel(tokenId);
    const uri = await nft.tokenURI(tokenId);
    const metadata = JSON.parse(atob(uri.replace("data:application/json;base64,", "")));

    const card = document.createElement("article");
    card.className = "card";
    const img = document.createElement("img");
    img.alt = `Feather level ${level}`;
    img.src = metadata.image;
    const caption = document.createElement("p");
    caption.textContent = `Level ${level}`;
    card.append(img, caption);
    els.gallery.appendChild(card);
  }
}

async function connect() {
  if (!window.ethereum) {
    els.walletStatus.textContent = "No wallet detected. Install MetaMask or Rabby.";
    return;
  }

  provider = new BrowserProvider(window.ethereum);
  const expected = BigInt(getConfig().chainId || "46630");
  const network = await provider.getNetwork();

  if (network.chainId !== expected) {
    try {
      await window.ethereum.request({
        method: "wallet_switchEthereumChain",
        params: [{ chainId: "0x" + expected.toString(16) }],
      });
    } catch {
      els.walletStatus.textContent = `Switch to chain ${expected} to continue.`;
      return;
    }
  }

  await provider.send("eth_requestAccounts", []);
  signer = await provider.getSigner();
  account = await signer.getAddress();
  bindContracts();

  els.walletStatus.textContent = `Connected: ${account}`;
  els.connectBtn.textContent = "Refresh";
  await refresh();
}

async function ensureWethAllowance(amount) {
  const config = getConfig();
  const current = await weth.allowance(account, config.swapRouterAddress);
  if (current >= amount) {
    return;
  }
  els.txStatus.textContent = "Approving WETH for swap router...";
  const approveTx = await weth.connect(signer).approve(config.swapRouterAddress, amount);
  await approveTx.wait();
}

async function swap() {
  if (!contractsReady()) {
    return;
  }

  const amount = parseEther(els.wethAmount.value || "0");
  if (amount <= 0n) {
    els.txStatus.textContent = "Enter a WETH amount.";
    return;
  }

  const config = getConfig();
  const poolKey = buildPoolKey(config);

  try {
    await ensureWethAllowance(amount);
    els.txStatus.textContent = "Submitting swap...";
    const tx = await swapRouter.connect(signer).buyInvestWithWeth(poolKey, amount);
    els.txStatus.textContent = `Waiting for ${tx.hash.slice(0, 10)}...`;
    await tx.wait();
    els.txStatus.textContent = "Swap confirmed. Volume will show after refresh.";
    await refresh();
  } catch (error) {
    els.txStatus.textContent = error.shortMessage || error.message || "Swap failed.";
  }
}

async function claim() {
  if (!nft || !signer) {
    return;
  }

  try {
    els.txStatus.textContent = "Submitting claim...";
    const tx = await nft.connect(signer).claimNextFeather();
    els.txStatus.textContent = `Waiting for ${tx.hash.slice(0, 10)}...`;
    await tx.wait();
    els.txStatus.textContent = "Claim confirmed.";
    await refresh();
  } catch (error) {
    els.txStatus.textContent = error.shortMessage || error.message || "Claim failed.";
  }
}

els.connectBtn.addEventListener("click", connect);
els.loadConfigBtn.addEventListener("click", loadDeploymentConfig);
els.saveConfigBtn.addEventListener("click", saveLocalConfig);
els.swapBtn.addEventListener("click", swap);
els.claimBtn.addEventListener("click", claim);

loadLocalConfig();
loadDeploymentConfig();
