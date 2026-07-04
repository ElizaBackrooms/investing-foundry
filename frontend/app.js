import { BrowserProvider, Contract, formatEther } from "https://cdn.jsdelivr.net/npm/ethers@6.13.5/+esm";

const NFT_ABI = [
  "function investAccumulated(address) view returns (uint256)",
  "function eligibleLevel(address) view returns (uint256)",
  "function highestLevel(address) view returns (uint256)",
  "function balanceOf(address) view returns (uint256)",
  "function tokenOfOwnerByIndex(address,uint256) view returns (uint256)",
  "function tokenIdToLevel(uint256) view returns (uint256)",
  "function tokenURI(uint256) view returns (string)",
  "function claimNextFeather()",
  "event FeatherClaimed(address indexed owner, uint256 indexed tokenId, uint256 level)",
];

const TOKENS_PER_LEVEL = 100_000n * 10n ** 18n;

const els = {
  connectBtn: document.getElementById("connectBtn"),
  walletStatus: document.getElementById("walletStatus"),
  accumulated: document.getElementById("accumulated"),
  eligible: document.getElementById("eligible"),
  claimed: document.getElementById("claimed"),
  pending: document.getElementById("pending"),
  claimBtn: document.getElementById("claimBtn"),
  txStatus: document.getElementById("txStatus"),
  gallery: document.getElementById("gallery"),
  nftAddress: document.getElementById("nftAddress"),
  chainId: document.getElementById("chainId"),
  saveConfigBtn: document.getElementById("saveConfigBtn"),
};

let provider;
let signer;
let account;
let nft;

function loadConfig() {
  els.nftAddress.value = localStorage.getItem("investing.nft") || "";
  els.chainId.value = localStorage.getItem("investing.chainId") || "46630";
}

function saveConfig() {
  localStorage.setItem("investing.nft", els.nftAddress.value.trim());
  localStorage.setItem("investing.chainId", els.chainId.value.trim());
  bindContract();
}

function bindContract() {
  const address = els.nftAddress.value.trim();
  nft = address && provider ? new Contract(address, NFT_ABI, signer || provider) : null;
}

function formatTokens(value) {
  return `${Number(formatEther(value)).toLocaleString(undefined, { maximumFractionDigits: 2 })} INVEST`;
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

  els.accumulated.textContent = formatTokens(accumulated);
  els.eligible.textContent = String(eligible);
  els.claimed.textContent = String(claimed);
  els.pending.textContent = String(pending);
  els.claimBtn.disabled = pending === 0n;

  els.gallery.innerHTML = "";
  for (let i = 0n; i < balance; i++) {
    const tokenId = await nft.tokenOfOwnerByIndex(account, i);
    const level = await nft.tokenIdToLevel(tokenId);
    const uri = await nft.tokenURI(tokenId);
    const metadata = JSON.parse(atob(uri.replace("data:application/json;base64,", "")));

    const card = document.createElement("article");
    card.className = "card";
    card.innerHTML = `<img alt="Feather level ${level}" src="${metadata.image}" /><p>Level ${level}</p>`;
    els.gallery.appendChild(card);
  }
}

async function connect() {
  if (!window.ethereum) {
    els.walletStatus.textContent = "No wallet detected. Install MetaMask or Rabby.";
    return;
  }

  provider = new BrowserProvider(window.ethereum);
  const network = await provider.getNetwork();
  const expected = BigInt(els.chainId.value || "46630");

  if (network.chainId !== expected) {
    try {
      await window.ethereum.request({
        method: "wallet_switchEthereumChain",
        params: [{ chainId: "0x" + expected.toString(16) }],
      });
    } catch (error) {
      els.walletStatus.textContent = `Switch to chain ${expected} to continue.`;
      return;
    }
  }

  await provider.send("eth_requestAccounts", []);
  signer = await provider.getSigner();
  account = await signer.getAddress();
  bindContract();

  els.walletStatus.textContent = `Connected: ${account}`;
  els.connectBtn.textContent = "Refresh";
  await refresh();
}

async function claim() {
  if (!nft || !signer) {
    return;
  }

  els.txStatus.textContent = "Submitting claim...";
  const tx = await nft.claimNextFeather();
  els.txStatus.textContent = `Waiting for ${tx.hash.slice(0, 10)}...`;
  await tx.wait();
  els.txStatus.textContent = "Claim confirmed.";
  await refresh();
}

els.connectBtn.addEventListener("click", connect);
els.claimBtn.addEventListener("click", claim);
els.saveConfigBtn.addEventListener("click", saveConfig);
loadConfig();
