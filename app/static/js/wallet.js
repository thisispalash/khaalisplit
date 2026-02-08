/**
 * wallet.js — Wallet connection and signing.
 *
 * Uses ethers.js v6 (local file). Falls back to injected provider on desktop.
 *
 * The client ONLY signs messages — never submits on-chain transactions.
 * All contract calls go through the Django backend via BACKEND_PRIVATE_KEY.
 */

// ────────────────────────────────────────────────────────
// State
// ────────────────────────────────────────────────────────

let provider = null;
let signer = null;

// ────────────────────────────────────────────────────────
// Chain + Token constants (testnet only, USDC only)
// Sourced from contracts/script/tokens.json
// ────────────────────────────────────────────────────────

const CHAIN_TOKENS = {
  11155111: { usdc: '0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238' },
  84532:    { usdc: '0x036CbD53842c5426634e7929541eC2318f3dCF7e' },
  421614:   { usdc: '0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d' },
  11155420: { usdc: '0x5fd84259d66Cd46123540766Be93DFE6D43130D7' },
  5042002:  { usdc: '0x3600000000000000000000000000000000000000' },
};

// Settlement contract addresses per chain (from contracts/deployments.json)
const SETTLEMENT_ADDRESSES = {
  11155111: '0xd038e9CD05a71765657Fd3943d41820F5035A6C1',
  84532:    '0xacDbabeDc22BE4eD68D9084Dd3157c27D7154baa',
  421614:   '0x8A20a346a00f809fbd279c1E8B56883998867254',
  11155420: '0x8A20a346a00f809fbd279c1E8B56883998867254',
  5042002:  '0xeB75548245A9C5a31ABF6Eda7CA16977f3Af3690',
};

// ────────────────────────────────────────────────────────
// Connection
// ────────────────────────────────────────────────────────

/**
 * Connect to the user's wallet (injected provider or WalletConnect).
 * Updates global Hyperscript state and dispatches walletChanged event.
 */
window.connectWallet = async function connectWallet() {
  try {
    // Get the actual provider, bypassing the proxy wrapper on window.ethereum
    // The proxy's selectExtension flow is broken in some MetaMask versions,
    // but the underlying providers[0] works fine.
    let injected = window.ethereum?.providers?.[0] || window.ethereum || null;

    if (injected) {
      // Request accounts directly via the raw provider — this works.
      // Then wrap with ethers using JsonRpcProvider pointed at the same RPC,
      // avoiding BrowserProvider which re-triggers the broken proxy.
      const accounts = await injected.request({ method: 'eth_requestAccounts' });
      const chainIdHex = await injected.request({ method: 'eth_chainId' });
      const address = accounts[0];
      const chainId = parseInt(chainIdHex, 16);

      // Use ethers JsonRpcProvider via the raw provider's request method
      provider = new ethers.BrowserProvider({
        request: (a) => injected.request(a),
        on: () => {},
        removeListener: () => {},
      });
      signer = await provider.getSigner(address);

      const network = await provider.getNetwork();

      // Update Hyperscript globals
      window.walletConnected = true;
      window.walletAddress = address;
      window.walletChainId = Number(network.chainId);

      // Dispatch event for Hyperscript listeners
      document.body.dispatchEvent(new CustomEvent('walletChanged'));

      console.log('[wallet] Connected:', address, 'Chain:', network.chainId);
      return address;
    }

    // TODO: WalletConnect / Web3Modal for mobile PWA
    console.warn('[wallet] No injected provider found. Mobile support coming soon.');
    alert('No wallet found. Please install MetaMask or use a dApp browser.');
    return null;

  } catch (err) {
    console.error('[wallet] Connection failed:', err);
    return null;
  }
};

/**
 * Disconnect wallet and reset state.
 */
window.disconnectWallet = function disconnectWallet() {
  provider = null;
  signer = null;
  window.walletConnected = false;
  window.walletAddress = '';
  window.walletChainId = 0;
  document.body.dispatchEvent(new CustomEvent('walletChanged'));
  console.log('[wallet] Disconnected');
};

// ────────────────────────────────────────────────────────
// Signing
// ────────────────────────────────────────────────────────

/**
 * Sign a message using EIP-191 personal_sign.
 * @param {string} message — The message to sign
 * @returns {string|null} The signature hex string, or null on failure
 */
window.signMessage = async function signMessage(message) {
  if (!signer) {
    console.error('[wallet] No signer available. Connect wallet first.');
    return null;
  }
  try {
    const signature = await signer.signMessage(message);
    console.log('[wallet] Signed message:', message.substring(0, 40) + '...');
    return signature;
  } catch (err) {
    console.error('[wallet] Signing failed:', err);
    return null;
  }
};

// ────────────────────────────────────────────────────────
// Utility getters
// ────────────────────────────────────────────────────────

/**
 * Get USDC address for a given chain ID.
 * @param {number} chainId
 * @returns {string|null}
 */
window.getUsdcAddress = function getUsdcAddress(chainId) {
  const tokens = CHAIN_TOKENS[chainId];
  return tokens ? tokens.usdc : null;
};

/**
 * Get settlement contract address for a given chain ID.
 * @param {number} chainId
 * @returns {string|null}
 */
window.getSettlementAddress = function getSettlementAddress(chainId) {
  return SETTLEMENT_ADDRESSES[chainId] || null;
};

// ────────────────────────────────────────────────────────
// Account change listeners
// ────────────────────────────────────────────────────────

{
  // Use the actual provider, not the proxy wrapper
  let listen = window.ethereum?.providers?.[0] || window.ethereum || null;

  if (listen) {
    listen.on('accountsChanged', async (accounts) => {
      if (accounts.length === 0) {
        window.disconnectWallet();
      } else if (signer) {
        const address = accounts[0];
        window.walletAddress = address;
        document.body.dispatchEvent(new CustomEvent('walletChanged'));
        console.log('[wallet] Account changed:', address);
      }
    });

    listen.on('chainChanged', (chainId) => {
      window.walletChainId = parseInt(chainId, 16);
      document.body.dispatchEvent(new CustomEvent('walletChanged'));
      console.log('[wallet] Chain changed:', window.walletChainId);
    });
  }
}
