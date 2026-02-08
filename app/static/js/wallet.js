/**
 * wallet.js — Wallet connection and signing.
 *
 * Uses ethers.js v6 (local file). Falls back to injected provider on desktop.
 *
 * The client ONLY signs messages — never submits on-chain transactions.
 * All contract calls go through the Django backend via BACKEND_PRIVATE_KEY.
 */

// ────────────────────────────────────────────────────────
// Mobile detection
// ────────────────────────────────────────────────────────

/**
 * Detect if the user is on a mobile device.
 * @returns {boolean}
 */
window.isMobile = function isMobile() {
  return /Android|iPhone|iPad|iPod|Opera Mini|IEMobile|WPDesktop/i.test(navigator.userAgent)
    || (navigator.maxTouchPoints > 0 && window.innerWidth < 768);
};

/**
 * Open MetaMask deep link on mobile.
 * Redirects to MetaMask's in-app browser with the current URL.
 */
window.openMetaMaskDeepLink = function openMetaMaskDeepLink() {
  const currentUrl = window.location.href.replace(/^https?:\/\//, '');
  const deepLink = `https://metamask.app.link/dapp/${currentUrl}`;
  window.location.href = deepLink;
};

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

    // Mobile: redirect to MetaMask deep link
    if (window.isMobile()) {
      console.log('[wallet] Mobile detected, opening MetaMask deep link');
      window.openMetaMaskDeepLink();
      return null;
    }

    console.warn('[wallet] No injected provider found.');
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
// Settlement signing
// ────────────────────────────────────────────────────────

/**
 * Sign a ERC-3009 transferWithAuthorization for USDC settlement.
 * The user signs an EIP-712 typed data message authorizing the
 * settlement contract to pull USDC from their wallet.
 *
 * @param {string} toAddress — recipient address (settlement contract)
 * @param {string} amount — amount in USDC (human-readable, e.g. "10.5")
 * @param {number} chainId — chain ID to settle on
 * @returns {Object|null} — { signature, auth_from, valid_after, valid_before, nonce }
 */
window.signSettlementAuthorization = async function signSettlementAuthorization(toAddress, amount, chainId) {
  if (!signer) {
    console.error('[wallet] No signer available. Connect wallet first.');
    return null;
  }
  try {
    const usdcAddress = getUsdcAddress(chainId);
    const settlementAddress = getSettlementAddress(chainId);
    if (!usdcAddress || !settlementAddress) {
      console.error('[wallet] No USDC or settlement address for chain', chainId);
      return null;
    }

    const from = await signer.getAddress();
    const amountWei = ethers.parseUnits(amount, 6); // USDC has 6 decimals
    const validAfter = 0;
    const validBefore = Math.floor(Date.now() / 1000) + 3600; // 1 hour
    const nonce = ethers.hexlify(ethers.randomBytes(32));

    // EIP-712 domain for USDC transferWithAuthorization
    const domain = {
      name: 'USD Coin',
      version: '2',
      chainId: chainId,
      verifyingContract: usdcAddress,
    };

    const types = {
      TransferWithAuthorization: [
        { name: 'from', type: 'address' },
        { name: 'to', type: 'address' },
        { name: 'value', type: 'uint256' },
        { name: 'validAfter', type: 'uint256' },
        { name: 'validBefore', type: 'uint256' },
        { name: 'nonce', type: 'bytes32' },
      ],
    };

    const value = {
      from: from,
      to: settlementAddress,
      value: amountWei,
      validAfter: validAfter,
      validBefore: validBefore,
      nonce: nonce,
    };

    const signature = await signer.signTypedData(domain, types, value);
    console.log('[wallet] Signed settlement authorization');

    return {
      signature,
      auth_from: from,
      valid_after: validAfter,
      valid_before: validBefore,
      nonce: nonce,
    };
  } catch (err) {
    console.error('[wallet] Settlement authorization signing failed:', err);
    return null;
  }
};

/**
 * Sign a Gateway BurnIntent for cross-chain USDC settlement.
 * @param {Object} burnIntent — burn intent object
 * @returns {Object|null} — { intent, signature }
 */
window.signGatewayBurnIntent = async function signGatewayBurnIntent(burnIntent) {
  if (!signer) {
    console.error('[wallet] No signer available.');
    return null;
  }
  try {
    // Sign the burn intent as a message for the hackathon
    const intentJson = JSON.stringify(burnIntent);
    const signature = await signer.signMessage(intentJson);
    console.log('[wallet] Signed gateway burn intent');

    return {
      intent: burnIntent,
      signature: signature,
    };
  } catch (err) {
    console.error('[wallet] Gateway burn intent signing failed:', err);
    return null;
  }
};

/**
 * Initiate a settlement via the backend API.
 * Handles the full flow: sign authorization → submit to backend → get tx hash.
 *
 * @param {string} toSubname — recipient's subname (e.g. "cool-tiger")
 * @param {string} amount — amount in USDC
 * @param {number} groupId — optional group ID for context
 * @param {string} type — "authorization" or "gateway"
 * @returns {Object|null} — { tx_hash, status } or null on failure
 */
window.initiateSettlement = async function initiateSettlement(toSubname, amount, groupId, type) {
  type = type || 'authorization';
  const chainId = window.walletChainId || 11155111;

  let body = {
    type: type,
    to_subname: toSubname,
    amount: amount,
    source_chain: chainId,
    dest_chain: chainId,
  };
  if (groupId) body.group_id = groupId;

  if (type === 'authorization') {
    const settlementAddr = getSettlementAddress(chainId);
    const authData = await signSettlementAuthorization(settlementAddr, amount, chainId);
    if (!authData) return null;
    Object.assign(body, authData);
  } else if (type === 'gateway') {
    // For cross-chain, we'd need the burn intent from an estimate call first
    // Simplified for hackathon
    const burnIntent = { amount, chainId };
    const signed = await signGatewayBurnIntent(burnIntent);
    if (!signed) return null;
    body.signed_burn_intent = signed;
  }

  try {
    const csrfToken = document.querySelector('[name=csrfmiddlewaretoken]')?.value ||
                      document.cookie.match(/csrftoken=([^;]+)/)?.[1] || '';
    const resp = await fetch('/api/settle/for-user/', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRFToken': csrfToken,
      },
      body: JSON.stringify(body),
    });

    const result = await resp.json();
    if (resp.ok) {
      console.log('[wallet] Settlement submitted:', result.tx_hash);
      return result;
    } else {
      console.error('[wallet] Settlement failed:', result.error);
      return null;
    }
  } catch (err) {
    console.error('[wallet] Settlement request failed:', err);
    return null;
  }
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
