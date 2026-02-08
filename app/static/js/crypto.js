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
     * Compute ECDH shared secret using ethers.js SigningKey.
     * Both parties derive the same shared secret from their private key
     * and the other's public key.
     *
     * @param {string} myPrivKeyHex — our private key (from signing a deterministic message)
     * @param {string} theirPubKeyHex — their uncompressed public key (hex, no 0x prefix)
     * @returns {Uint8Array} — 32-byte shared secret
     */
    computeSharedSecret(myPrivKeyHex, theirPubKeyHex) {
      if (!window.ethers) {
        throw new Error('ethers.js required for ECDH');
      }
      const signingKey = new window.ethers.SigningKey('0x' + myPrivKeyHex);
      // computeSharedSecret expects the full uncompressed pubkey with 0x04 prefix
      const pubKeyWithPrefix = theirPubKeyHex.startsWith('04')
        ? '0x' + theirPubKeyHex
        : '0x04' + theirPubKeyHex;
      const sharedHex = signingKey.computeSharedSecret(pubKeyWithPrefix);
      return window.ethers.getBytes(sharedHex);
    },

    /**
     * Encrypt a group key for a specific member using ECDH.
     * Uses a deterministic signing key derived from the wallet signature
     * and the member's registered public key.
     *
     * @param {string} memberPubKeyHex — member's uncompressed public key (hex, no 0x)
     * @param {string} groupKeyHex — the group symmetric key to encrypt (hex)
     * @returns {Promise<string>} — encrypted group key (hex)
     */
    async encryptGroupKeyForMember(memberPubKeyHex, groupKeyHex) {
      if (!window.ethers) {
        throw new Error('ethers.js required for ECDH');
      }

      // Sign a deterministic message to derive a consistent private key for ECDH
      const ecdhMsg = 'khaaliSplit ECDH key exchange v1';
      const sig = await window.signMessage(ecdhMsg);
      if (!sig) throw new Error('Failed to sign ECDH message');

      // Use the first 32 bytes of the signature hash as our ECDH private key
      const privKey = window.ethers.keccak256(window.ethers.toUtf8Bytes(sig)).slice(2);

      // Compute ECDH shared secret
      const sharedSecret = this.computeSharedSecret(privKey, memberPubKeyHex);

      // Derive AES key from shared secret via HKDF
      const baseKey = await crypto.subtle.importKey(
        'raw', sharedSecret, 'HKDF', false, ['deriveKey']
      );
      const encoder = new TextEncoder();
      const derivedKey = await crypto.subtle.deriveKey(
        { name: 'HKDF', hash: 'SHA-256', salt: encoder.encode('khaaliSplit-ecdh'), info: encoder.encode('group-key-wrap') },
        baseKey,
        { name: 'AES-GCM', length: 256 },
        false,
        ['encrypt']
      );

      // Encrypt the group key
      const groupKeyBytes = hexToBuf(groupKeyHex);
      const iv = crypto.getRandomValues(new Uint8Array(12));
      const encrypted = await crypto.subtle.encrypt(
        { name: 'AES-GCM', iv, tagLength: 128 },
        derivedKey,
        groupKeyBytes
      );

      const combined = new Uint8Array(iv.length + encrypted.byteLength);
      combined.set(iv);
      combined.set(new Uint8Array(encrypted), iv.length);

      return bufToHex(combined);
    },

    /**
     * Decrypt a group key that was encrypted for us via ECDH.
     * Mirror of encryptGroupKeyForMember.
     *
     * @param {string} senderPubKeyHex — sender's uncompressed public key (hex, no 0x)
     * @param {string} encryptedKeyHex — encrypted group key (hex)
     * @returns {Promise<string>} — decrypted group key (hex)
     */
    async decryptGroupKeyFromMember(senderPubKeyHex, encryptedKeyHex) {
      if (!window.ethers) {
        throw new Error('ethers.js required for ECDH');
      }

      const ecdhMsg = 'khaaliSplit ECDH key exchange v1';
      const sig = await window.signMessage(ecdhMsg);
      if (!sig) throw new Error('Failed to sign ECDH message');

      const privKey = window.ethers.keccak256(window.ethers.toUtf8Bytes(sig)).slice(2);
      const sharedSecret = this.computeSharedSecret(privKey, senderPubKeyHex);

      const baseKey = await crypto.subtle.importKey(
        'raw', sharedSecret, 'HKDF', false, ['deriveKey']
      );
      const encoder = new TextEncoder();
      const derivedKey = await crypto.subtle.deriveKey(
        { name: 'HKDF', hash: 'SHA-256', salt: encoder.encode('khaaliSplit-ecdh'), info: encoder.encode('group-key-wrap') },
        baseKey,
        { name: 'AES-GCM', length: 256 },
        false,
        ['decrypt']
      );

      const combined = hexToBuf(encryptedKeyHex);
      const iv = combined.slice(0, 12);
      const data = combined.slice(12);

      const decrypted = await crypto.subtle.decrypt(
        { name: 'AES-GCM', iv, tagLength: 128 },
        derivedKey,
        data
      );

      return bufToHex(new Uint8Array(decrypted));
    },

    /**
     * Get our ECDH public key derived from the wallet signature.
     * This is different from the wallet address — it's a deterministic
     * key pair used specifically for ECDH key exchange.
     * @returns {Promise<string>} — uncompressed public key (hex, no 0x)
     */
    async getEcdhPublicKey() {
      if (!window.ethers) throw new Error('ethers.js required');

      const ecdhMsg = 'khaaliSplit ECDH key exchange v1';
      const sig = await window.signMessage(ecdhMsg);
      if (!sig) throw new Error('Failed to sign ECDH message');

      const privKey = window.ethers.keccak256(window.ethers.toUtf8Bytes(sig)).slice(2);
      const signingKey = new window.ethers.SigningKey('0x' + privKey);
      // Return uncompressed public key without 0x prefix
      return signingKey.publicKey.slice(2);
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
