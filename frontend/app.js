import { BrowserProvider, Contract, formatEther, parseEther } from "https://cdn.jsdelivr.net/npm/ethers@6.13.5/+esm";

const TOKENS_PER_LEVEL = 100_000n * 10n ** 18n;
const MIN_SWAP_VOLUME = 1_000n * 10n ** 18n;
const MAX_CLAIM_PER_TX = 20n;
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

const NETWORK_PRESETS = {
  testnet: {
    chainId: 46630,
    chainName: "Robinhood Chain Testnet",
    rpcUrl: "https://rpc.testnet.chain.robinhood.com",
    explorerUrl: "https://explorer.testnet.chain.robinhood.com",
    nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
    configFile: "config.testnet.json",
  },
  mainnet: {
    chainId: 4663,
    chainName: "Robinhood Chain",
    rpcUrl: "https://rpc.mainnet.chain.robinhood.com",
    explorerUrl: "https://robinhoodchain.blockscout.com",
    nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
    configFile: "config.mainnet.json",
  },
};

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
  "explorerUrl",
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
  addNetworkBtn: document.getElementById("addNetworkBtn"),
  loadConfigBtn: document.getElementById("loadConfigBtn"),
  networkSelect: document.getElementById("networkSelect"),
  walletStatus: document.getElementById("walletStatus"),
  minSwapHint: document.getElementById("minSwapHint"),
  wethAmount: document.getElementById("wethAmount"),
  maxWethBtn: document.getElementById("maxWethBtn"),
  wethBalance: document.getElementById("wethBalance"),
  swapHint: document.getElementById("swapHint"),
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
  explorerUrl: document.getElementById("explorerUrl"),
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
let wethBalanceWei = 0n;
let claiming = false;

function getSelectedNetwork() {
  return els.networkSelect.value in NETWORK_PRESETS ? els.networkSelect.value : "testnet";
}

function getNetworkPreset(network = getSelectedNetwork()) {
  return NETWORK_PRESETS[network];
}

function isConfiguredAddress(value) {
  return Boolean(value && value !== ZERO_ADDRESS);
}

function getConfig() {
  return {
    chainId: els.chainId.value.trim(),
    explorerUrl: els.explorerUrl.value.trim(),
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

function applyNetworkPreset(network = getSelectedNetwork()) {
  const preset = getNetworkPreset(network);
  els.chainId.value = String(preset.chainId);
  if (!els.explorerUrl.value.trim()) {
    els.explorerUrl.value = preset.explorerUrl;
  }
}

function applyConfig(config) {
  const mapping = {
    chainId: config.chainId,
    explorerUrl: config.explorerUrl,
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

  const preset = getNetworkPreset();
  if (!els.explorerUrl.value.trim()) {
    els.explorerUrl.value = preset.explorerUrl;
  }
}

function loadLocalConfig() {
  const storedNetwork = localStorage.getItem("investing.network");
  if (storedNetwork && NETWORK_PRESETS[storedNetwork]) {
    els.networkSelect.value = storedNetwork;
  }

  applyNetworkPreset();

  for (const key of CONFIG_KEYS) {
    const stored = localStorage.getItem(`investing.${key}`);
    if (stored && els[key]) {
      els[key].value = stored;
    }
  }
}

function saveLocalConfig() {
  const config = getConfig();
  localStorage.setItem("investing.network", getSelectedNetwork());
  for (const key of CONFIG_KEYS) {
    localStorage.setItem(`investing.${key}`, String(config[key]));
  }
  bindContracts();
  updateSwapUi();
  setTxStatus("Saved contract config locally.");
}

async function loadDeploymentConfig(network = getSelectedNetwork()) {
  const preset = getNetworkPreset(network);
  const candidates = [`./${preset.configFile}`, "./config.json"];

  for (const path of candidates) {
    try {
      const response = await fetch(path, { cache: "no-store" });
      if (!response.ok) {
        continue;
      }
      const config = await response.json();
      applyConfig(config);
      saveLocalConfig();
      setTxStatus(`Loaded ${path}.`);
      return true;
    } catch {
      // try next candidate
    }
  }

  applyNetworkPreset(network);
  updateSwapUi();
  setTxStatus(
    `No ${preset.configFile} found. Copy deployments manifest to frontend/${preset.configFile} after deploy.`,
    null,
    true
  );
  return false;
}

function bindContracts() {
  const config = getConfig();
  if (!provider) {
    return;
  }

  nft = isConfiguredAddress(config.nftAddress)
    ? new Contract(config.nftAddress, NFT_ABI, signer || provider)
    : null;
  swapRouter = isConfiguredAddress(config.swapRouterAddress)
    ? new Contract(config.swapRouterAddress, ROUTER_ABI, signer || provider)
    : null;
  weth = isConfiguredAddress(config.wethAddress)
    ? new Contract(config.wethAddress, ERC20_ABI, signer || provider)
    : null;
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

function swapConfigIssues() {
  const config = getConfig();
  const issues = [];

  if (!account) {
    issues.push("connect your wallet");
  }
  if (!isConfiguredAddress(config.swapRouterAddress)) {
    issues.push("set swap router address");
  }
  if (!isConfiguredAddress(config.wethAddress)) {
    issues.push("set WETH address");
  }
  if (!isConfiguredAddress(config.hookAddress)) {
    issues.push("set hook address");
  }
  if (!isConfiguredAddress(config.currency0)) {
    issues.push("set currency 0");
  }
  if (!isConfiguredAddress(config.currency1)) {
    issues.push("set currency 1");
  }
  if (!swapRouter || !weth) {
    issues.push("finish contract config");
  }

  return issues;
}

function contractsReady() {
  return swapConfigIssues().length === 0;
}

function txExplorerUrl(hash) {
  const explorer = getConfig().explorerUrl || getNetworkPreset().explorerUrl;
  if (!explorer || !hash) {
    return null;
  }
  return `${explorer.replace(/\/$/, "")}/tx/${hash}`;
}

function setTxStatus(message, txHash = null, warn = false) {
  els.txStatus.className = warn ? "status warn" : "status";
  els.txStatus.textContent = "";

  const text = document.createElement("span");
  text.textContent = message;
  els.txStatus.appendChild(text);

  const url = txExplorerUrl(txHash);
  if (url) {
    const link = document.createElement("a");
    link.href = url;
    link.target = "_blank";
    link.rel = "noopener noreferrer";
    link.textContent = "View on explorer";
    els.txStatus.appendChild(link);
  }
}

function updateSwapUi() {
  const issues = swapConfigIssues();
  const ready = issues.length === 0;
  els.swapBtn.disabled = !ready;
  els.maxWethBtn.disabled = !ready || wethBalanceWei === 0n;

  if (!ready) {
    els.swapHint.textContent = `Swap disabled: ${issues.join(", ")}.`;
    els.swapHint.className = "status warn";
    return;
  }

  els.swapHint.textContent = "";
  els.swapHint.className = "status";
}

function buildAddChainParams(preset) {
  return {
    chainId: "0x" + BigInt(preset.chainId).toString(16),
    chainName: preset.chainName,
    nativeCurrency: preset.nativeCurrency,
    rpcUrls: [preset.rpcUrl],
    blockExplorerUrls: [preset.explorerUrl],
  };
}

async function addRobinhoodNetwork(network = getSelectedNetwork()) {
  if (!window.ethereum) {
    setTxStatus("No wallet detected. Install MetaMask or Rabby.", null, true);
    return false;
  }

  const preset = getNetworkPreset(network);
  try {
    await window.ethereum.request({
      method: "wallet_addEthereumChain",
      params: [buildAddChainParams(preset)],
    });
    setTxStatus(`Added ${preset.chainName} to your wallet.`);
    return true;
  } catch (error) {
    setTxStatus(error.shortMessage || error.message || "Failed to add network.", null, true);
    return false;
  }
}

async function switchWalletChain(chainId) {
  if (!window.ethereum) {
    return false;
  }

  const expected = BigInt(chainId);
  const hexChainId = "0x" + expected.toString(16);

  try {
    await window.ethereum.request({
      method: "wallet_switchEthereumChain",
      params: [{ chainId: hexChainId }],
    });
    return true;
  } catch (error) {
    if (error?.code === 4902) {
      const network = Object.values(NETWORK_PRESETS).find((preset) => BigInt(preset.chainId) === expected);
      if (!network) {
        setTxStatus(`Unknown chain ${expected}. Add it manually.`, null, true);
        return false;
      }
      await window.ethereum.request({
        method: "wallet_addEthereumChain",
        params: [buildAddChainParams(network)],
      });
      return true;
    }

    setTxStatus(error.shortMessage || error.message || `Switch to chain ${expected} to continue.`, null, true);
    return false;
  }
}

async function onNetworkChange() {
  const network = getSelectedNetwork();
  localStorage.setItem("investing.network", network);
  applyNetworkPreset(network);
  await loadDeploymentConfig(network);

  if (provider) {
    provider = new BrowserProvider(window.ethereum);
    const switched = await switchWalletChain(getConfig().chainId);
    if (switched) {
      signer = await provider.getSigner();
      bindContracts();
      await refresh();
    }
  }
}

async function refresh() {
  els.minSwapHint.textContent = `Minimum counted buy volume per swap: ${formatTokens(MIN_SWAP_VOLUME)}`;

  if (!account || !nft) {
    updateSwapUi();
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
  els.progressDetail.textContent = `${formatTokens(intoLevel)} / ${formatTokens(TOKENS_PER_LEVEL)} toward next level`;

  els.claimBtn.disabled = pending === 0n || claiming;
  if (pending > MAX_CLAIM_PER_TX) {
    els.claimBtn.textContent = `Claim all ${pending} feathers (auto, ${MAX_CLAIM_PER_TX}/tx)`;
  } else if (pending > 0n) {
    els.claimBtn.textContent = `Claim ${pending} Feather${pending === 1n ? "" : "s"}`;
  } else {
    els.claimBtn.textContent = "Claim Feathers (max 20 / tx)";
  }

  if (weth) {
    wethBalanceWei = await weth.balanceOf(account);
    els.wethBalance.textContent = `WETH balance: ${formatEther(wethBalanceWei)}`;
  } else {
    wethBalanceWei = 0n;
    els.wethBalance.textContent = "WETH balance: —";
  }

  updateSwapUi();

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
  const expected = BigInt(getConfig().chainId || getNetworkPreset().chainId);
  const network = await provider.getNetwork();

  if (network.chainId !== expected) {
    const switched = await switchWalletChain(expected);
    if (!switched) {
      return;
    }
    provider = new BrowserProvider(window.ethereum);
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
    return null;
  }
  setTxStatus("Approving WETH for swap router...");
  const approveTx = await weth.connect(signer).approve(config.swapRouterAddress, amount);
  setTxStatus("Waiting for approval...", approveTx.hash);
  await approveTx.wait();
  return approveTx.hash;
}

async function swap() {
  if (!contractsReady()) {
    updateSwapUi();
    return;
  }

  const amount = parseEther(els.wethAmount.value || "0");
  if (amount <= 0n) {
    setTxStatus("Enter a WETH amount.", null, true);
    return;
  }

  const config = getConfig();
  const poolKey = buildPoolKey(config);

  try {
    await ensureWethAllowance(amount);
    setTxStatus("Submitting swap...");
    const tx = await swapRouter.connect(signer).buyInvestWithWeth(poolKey, amount);
    setTxStatus("Waiting for swap confirmation...", tx.hash);
    await tx.wait();
    setTxStatus("Swap confirmed. Volume will show after refresh.", tx.hash);
    await refresh();
  } catch (error) {
    setTxStatus(error.shortMessage || error.message || "Swap failed.", null, true);
  }
}

function setMaxWeth() {
  if (wethBalanceWei <= 0n) {
    return;
  }
  els.wethAmount.value = formatEther(wethBalanceWei);
}

async function getPendingFeathers() {
  const [eligible, claimed] = await Promise.all([
    nft.eligibleLevel(account),
    nft.highestLevel(account),
  ]);
  return eligible > claimed ? eligible - claimed : 0n;
}

async function claim() {
  if (!nft || !signer || claiming) {
    return;
  }

  claiming = true;
  els.claimBtn.disabled = true;

  let txCount = 0;
  let lastHash = null;

  try {
    let pending = await getPendingFeathers();
    if (pending === 0n) {
      setTxStatus("Nothing to claim.");
      await refresh();
      return;
    }

    const autoLoop = pending > MAX_CLAIM_PER_TX;

    while (pending > 0n) {
      txCount += 1;
      const batch = pending > MAX_CLAIM_PER_TX ? MAX_CLAIM_PER_TX : pending;

      if (autoLoop) {
        setTxStatus(`Claim ${txCount}: submitting ${batch} of ${pending} pending feathers...`);
      } else {
        setTxStatus("Submitting claim...");
      }

      const tx = await nft.connect(signer).claimNextFeather();
      lastHash = tx.hash;

      if (autoLoop) {
        setTxStatus(`Claim ${txCount}: waiting for confirmation (${batch} feathers)...`, tx.hash);
      } else {
        setTxStatus("Waiting for claim confirmation...", tx.hash);
      }

      await tx.wait();

      pending = await getPendingFeathers();

      if (autoLoop) {
        if (pending > 0n) {
          setTxStatus(`Claim ${txCount} confirmed. ${pending} feathers remaining...`, tx.hash);
        } else {
          setTxStatus(`All feathers claimed in ${txCount} transactions.`, tx.hash);
        }
      } else {
        setTxStatus("Claim confirmed.", tx.hash);
      }
    }

    await refresh();
  } catch (error) {
    const prefix = txCount > 0 ? `Stopped after claim ${txCount}: ` : "";
    setTxStatus(`${prefix}${error.shortMessage || error.message || "Claim failed."}`, lastHash, true);
    await refresh();
  } finally {
    claiming = false;
  }
}

els.connectBtn.addEventListener("click", connect);
els.addNetworkBtn.addEventListener("click", () => addRobinhoodNetwork());
els.loadConfigBtn.addEventListener("click", () => loadDeploymentConfig());
els.networkSelect.addEventListener("change", onNetworkChange);
els.saveConfigBtn.addEventListener("click", saveLocalConfig);
els.swapBtn.addEventListener("click", swap);
els.maxWethBtn.addEventListener("click", setMaxWeth);
els.claimBtn.addEventListener("click", claim);

loadLocalConfig();
loadDeploymentConfig();
updateSwapUi();
