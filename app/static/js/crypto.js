/**
 * crypto.js — Client-side encryption for khaaliSplit
 *
 * Uses Web Crypto API for AES-256-GCM encryption/decryption.
 * Group keys are derived from ECDH shared secrets via HKDF.
 *
 * Exposed globally as `window.khaaliCrypto`.
 */
(function () {
  'use strict';

  const khaaliCrypto = {
    groupKey: null,   // CryptoKey for current group
    _rawKey: null,    // raw bytes for debugging (Uint8Array)

    /**
     * Generate a fresh 256-bit AES key for a new group.
     * @returns {Promise<{key: CryptoKey, exported: string}>}
     */
    async generateGroupKey() {
      const key = await crypto.subtle.generateKey(
        { name: 'AES-GCM', length: 256 },
        true,  // extractable so we can share it
        ['encrypt', 'decrypt']
      );
      const raw = await crypto.subtle.exportKey('raw', key);
      const exported = bufToHex(new Uint8Array(raw));
      return { key, exported };
    },

    /**
     * Import a hex-encoded 256-bit key for an existing group.
     * @param {string} hexKey — 64-char hex string
     * @returns {Promise<CryptoKey>}
     */
    async importGroupKey(hexKey) {
      const raw = hexToBuf(hexKey);
      const key = await crypto.subtle.importKey(
        'raw',
        raw,
        { name: 'AES-GCM', length: 256 },
        true,
        ['encrypt', 'decrypt']
      );
      this.groupKey = key;
      this._rawKey = raw;
      return key;
    },

    /**
     * Derive an AES-256 group key from an ECDH shared secret.
     * Uses HKDF with SHA-256, salt = group_id, info = 'khaaliSplit-group-key'.
     * @param {Uint8Array} sharedSecret — raw ECDH shared secret bytes
     * @param {string} groupId — group identifier for salt
     * @returns {Promise<CryptoKey>}
     */
    async deriveGroupKey(sharedSecret, groupId) {
      // Import shared secret as HKDF base material
      const baseKey = await crypto.subtle.importKey(
        'raw',
        sharedSecret,
        'HKDF',
        false,
        ['deriveKey']
      );

      const encoder = new TextEncoder();
      const salt = encoder.encode(groupId.toString());
      const info = encoder.encode('khaaliSplit-group-key');

      const derivedKey = await crypto.subtle.deriveKey(
        { name: 'HKDF', hash: 'SHA-256', salt, info },
        baseKey,
        { name: 'AES-GCM', length: 256 },
        true,
        ['encrypt', 'decrypt']
      );

      this.groupKey = derivedKey;
      const raw = await crypto.subtle.exportKey('raw', derivedKey);
      this._rawKey = new Uint8Array(raw);
      return derivedKey;
    },

    /**
     * Encrypt plaintext with AES-256-GCM.
     * @param {string} plaintext — JSON string to encrypt
     * @returns {Promise<{ciphertext: string, hash: string}>}
     *   ciphertext — hex-encoded (iv + ciphertext + tag)
     *   hash — keccak256 of plaintext (for on-chain data_hash)
     */
    async encrypt(plaintext) {
      if (!this.groupKey) {
        throw new Error('No group key set. Call importGroupKey or deriveGroupKey first.');
      }

      const encoder = new TextEncoder();
      const data = encoder.encode(plaintext);

      // 12-byte random IV (recommended for AES-GCM)
      const iv = crypto.getRandomValues(new Uint8Array(12));

      const encrypted = await crypto.subtle.encrypt(
        { name: 'AES-GCM', iv, tagLength: 128 },
        this.groupKey,
        data
      );

      // Combine: iv (12) + ciphertext+tag
      const combined = new Uint8Array(iv.length + encrypted.byteLength);
      combined.set(iv);
      combined.set(new Uint8Array(encrypted), iv.length);

      const ciphertext = bufToHex(combined);

      // Hash plaintext for on-chain data_hash (using ethers if available)
      let hash = '';
      if (window.ethers) {
        hash = window.ethers.keccak256(encoder.encode(plaintext));
      } else {
        // Fallback: SHA-256 via Web Crypto
        const hashBuf = await crypto.subtle.digest('SHA-256', data);
        hash = '0x' + bufToHex(new Uint8Array(hashBuf));
      }

      return { ciphertext, hash };
    },

    /**
     * Decrypt AES-256-GCM ciphertext.
     * @param {string} ciphertextHex — hex-encoded (iv + ciphertext + tag)
     * @returns {Promise<string|null>} — decrypted plaintext, or null on failure
     */
    async decrypt(ciphertextHex) {
      if (!this.groupKey) return null;
      if (!ciphertextHex) return null;

      try {
        const combined = hexToBuf(ciphertextHex);
        const iv = combined.slice(0, 12);
        const data = combined.slice(12);

        const decrypted = await crypto.subtle.decrypt(
          { name: 'AES-GCM', iv, tagLength: 128 },
          this.groupKey,
          data
        );

        return new TextDecoder().decode(decrypted);
      } catch (err) {
        console.warn('[khaaliCrypto] Decryption failed:', err.message);
        return null;
      }
    },

    /**
     * Encrypt a group key for a specific member using their public key.
     * Uses ECDH to derive a shared secret, then encrypts the group key
     * with AES-256-GCM using the derived key.
     * @param {string} memberPubKeyHex — member's uncompressed public key (hex)
     * @param {string} groupKeyHex — the group symmetric key to encrypt
     * @returns {Promise<string>} — encrypted group key (hex)
     */
    async encryptGroupKeyForMember(memberPubKeyHex, groupKeyHex) {
      if (!window.ethers) {
        throw new Error('ethers.js required for ECDH');
      }

      // Get our private key from connected wallet (via signing)
      const provider = new window.ethers.BrowserProvider(window.ethereum);
      const signer = await provider.getSigner();

      // We use a deterministic "key exchange message" that both sides know
      const msg = 'khaaliSplit key exchange';
      const sig = await signer.signMessage(msg);

      // Derive shared secret: use our signing key + their pub key
      // In practice, this would use proper ECDH. For now, derive from
      // the signature as a seed (simplified for hackathon).
      const sharedSecret = window.ethers.keccak256(
        window.ethers.concat([
          window.ethers.toUtf8Bytes(sig),
          window.ethers.getBytes('0x' + memberPubKeyHex),
        ])
      );

      // Use shared secret to encrypt group key
      const sharedKeyBytes = window.ethers.getBytes(sharedSecret);
      const importedKey = await crypto.subtle.importKey(
        'raw',
        sharedKeyBytes,
        { name: 'AES-GCM', length: 256 },
        false,
        ['encrypt']
      );

      const groupKeyBytes = hexToBuf(groupKeyHex);
      const iv = crypto.getRandomValues(new Uint8Array(12));
      const encrypted = await crypto.subtle.encrypt(
        { name: 'AES-GCM', iv, tagLength: 128 },
        importedKey,
        groupKeyBytes
      );

      const combined = new Uint8Array(iv.length + encrypted.byteLength);
      combined.set(iv);
      combined.set(new Uint8Array(encrypted), iv.length);

      return bufToHex(combined);
    },

    /**
     * Clear the current group key from memory.
     */
    clearKey() {
      this.groupKey = null;
      this._rawKey = null;
    },
  };

  // --- Helpers ---

  function bufToHex(buf) {
    return Array.from(buf).map(b => b.toString(16).padStart(2, '0')).join('');
  }

  function hexToBuf(hex) {
    const clean = hex.startsWith('0x') ? hex.slice(2) : hex;
    const bytes = new Uint8Array(clean.length / 2);
    for (let i = 0; i < bytes.length; i++) {
      bytes[i] = parseInt(clean.substr(i * 2, 2), 16);
    }
    return bytes;
  }

  // Expose globally
  window.khaaliCrypto = khaaliCrypto;
})();
