/**
 * wallet.js — Wallet connection, signing, and contract interactions.
 *
 * Uses ethers.js v6 (local file). Falls back to injected provider on desktop.
 * TODO: Add Web3Modal / WalletConnect for mobile PWA deep linking.
 */

// ────────────────────────────────────────────────────────
// State
// ────────────────────────────────────────────────────────

let provider = null;
let signer = null;

// ────────────────────────────────────────────────────────
// Connection
// ────────────────────────────────────────────────────────

/**
 * Connect to the user's wallet (injected provider or WalletConnect).
 * Updates global Hyperscript state and dispatches walletChanged event.
 */
window.connectWallet = async function connectWallet() {
  try {
    // Check for injected provider (MetaMask, Rabby, etc.)
    if (typeof window.ethereum !== 'undefined') {
      provider = new ethers.BrowserProvider(window.ethereum);
      await provider.send('eth_requestAccounts', []);
      signer = await provider.getSigner();

      const address = await signer.getAddress();
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
// Account change listeners
// ────────────────────────────────────────────────────────

if (typeof window.ethereum !== 'undefined') {
  window.ethereum.on('accountsChanged', async (accounts) => {
    if (accounts.length === 0) {
      window.disconnectWallet();
    } else if (signer) {
      const address = accounts[0];
      window.walletAddress = address;
      document.body.dispatchEvent(new CustomEvent('walletChanged'));
      console.log('[wallet] Account changed:', address);
    }
  });

  window.ethereum.on('chainChanged', (chainId) => {
    window.walletChainId = parseInt(chainId, 16);
    document.body.dispatchEvent(new CustomEvent('walletChanged'));
    console.log('[wallet] Chain changed:', window.walletChainId);
  });
}
