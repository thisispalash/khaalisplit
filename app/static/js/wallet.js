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
// Contract constants
// ────────────────────────────────────────────────────────

const CHAIN_TOKENS = {
  11155111: { usdc: '0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238', eurc: '0x08210F9170F89Ab7658F0B5E3fF39b0E03C594D4' },
  8453:     { usdc: '0x036CbD53842c5426634e7929541eC2318f3dCF7e', eurc: '0x808456652fdb597867f38412077A9182bf77359F' },
  42161:    { usdc: '0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d', eurc: '0x0000000000000000000000000000000000000000' },
  43113:    { usdc: '0x5425890298aed601595a70AB815c96711a31Bc65', eurc: '0x5E44db7996c682E92a960b65AC713a54AD815c6B' },
  11155420: { usdc: '0x5fd84259d66Cd46123540766Be93DFE6D43130D7', eurc: '0x0000000000000000000000000000000000000000' },
};

// Settlement contract — same CREATE2 address across all chains
const SETTLEMENT_ADDRESS = window.SETTLEMENT_CONTRACT || '0x0000000000000000000000000000000000000000';

const SETTLEMENT_ABI = [
  'function settleWithPermit(address token, address sender, address recipient, uint256 destChainId, uint256 amount, bytes note, uint256 deadline, uint8 v, bytes32 r, bytes32 s)',
];

const ERC20_PERMIT_ABI = [
  'function name() view returns (string)',
  'function nonces(address) view returns (uint256)',
  'function DOMAIN_SEPARATOR() view returns (bytes32)',
  'function decimals() view returns (uint8)',
];

// ────────────────────────────────────────────────────────
// EIP-2612 Permit + Settlement
// ────────────────────────────────────────────────────────

/**
 * Sign an EIP-2612 permit and call settleWithPermit on-chain.
 * @param {string} recipient — recipient address
 * @param {string} amount — human-readable amount (e.g., "10.50")
 * @param {number} groupId — group ID for backend tracking
 * @param {number} [destChainId] — destination chain (defaults to current chain)
 * @returns {Promise<{hash: string}>} — tx hash
 */
window.settleWithPermit = async function settleWithPermit(recipient, amount, groupId, destChainId) {
  if (!signer || !provider) {
    throw new Error('Wallet not connected');
  }

  const network = await provider.getNetwork();
  const chainId = Number(network.chainId);
  destChainId = destChainId ? Number(destChainId) : chainId;

  const tokens = CHAIN_TOKENS[chainId];
  if (!tokens || !tokens.usdc) {
    throw new Error(`Unsupported chain: ${chainId}`);
  }

  const tokenAddress = tokens.usdc;
  const tokenContract = new ethers.Contract(tokenAddress, ERC20_PERMIT_ABI, provider);

  // Get token details for permit
  const [tokenName, decimals, nonce] = await Promise.all([
    tokenContract.name(),
    tokenContract.decimals(),
    tokenContract.nonces(await signer.getAddress()),
  ]);

  // Parse amount to token units
  const amountBN = ethers.parseUnits(amount, decimals);
  const deadline = Math.floor(Date.now() / 1000) + 3600; // 1 hour from now
  const sender = await signer.getAddress();

  // EIP-2612 permit typed data
  const domain = {
    name: tokenName,
    version: '1',
    chainId: chainId,
    verifyingContract: tokenAddress,
  };

  const types = {
    Permit: [
      { name: 'owner', type: 'address' },
      { name: 'spender', type: 'address' },
      { name: 'value', type: 'uint256' },
      { name: 'nonce', type: 'uint256' },
      { name: 'deadline', type: 'uint256' },
    ],
  };

  const value = {
    owner: sender,
    spender: SETTLEMENT_ADDRESS,
    value: amountBN,
    nonce: nonce,
    deadline: deadline,
  };

  // Sign the permit (EIP-712)
  console.log('[wallet] Requesting permit signature...');
  const signature = await signer.signTypedData(domain, types, value);
  const { v, r, s } = ethers.Signature.from(signature);

  // Call settleWithPermit
  const settlement = new ethers.Contract(SETTLEMENT_ADDRESS, SETTLEMENT_ABI, signer);
  const note = ethers.toUtf8Bytes(''); // empty note for now

  console.log('[wallet] Submitting settlement tx...');
  const tx = await settlement.settleWithPermit(
    tokenAddress,
    sender,
    recipient,
    destChainId,
    amountBN,
    note,
    deadline,
    v, r, s
  );

  console.log('[wallet] Settlement tx submitted:', tx.hash);

  // Report to backend
  const csrfToken = document.querySelector('[name=csrfmiddlewaretoken]')?.value || '';
  try {
    await fetch(`/api/settle/${groupId}/initiate/`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'X-CSRFToken': csrfToken,
      },
      body: new URLSearchParams({
        tx_hash: tx.hash,
        to_address: recipient,
        amount: amount,
        token: 'usdc',
        source_chain: chainId.toString(),
        dest_chain: destChainId.toString(),
      }),
    });
  } catch (err) {
    console.warn('[wallet] Failed to report settlement to backend:', err);
  }

  return { hash: tx.hash };
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
