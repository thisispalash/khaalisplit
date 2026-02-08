/**
 * keystore.js — IndexedDB key storage for khaaliSplit
 *
 * Stores ECDH shared secrets and group symmetric keys in IndexedDB
 * so users don't need to re-derive them every session.
 *
 * Exposed globally as `window.khaaliKeystore`.
 */
(function () {
  'use strict';

  const DB_NAME = 'khaaliSplit-keystore';
  const DB_VERSION = 1;
  const STORE_NAME = 'keys';

  let db = null;

  /**
   * Open (or create) the IndexedDB database.
   * @returns {Promise<IDBDatabase>}
   */
  function openDB() {
    if (db) return Promise.resolve(db);

    return new Promise((resolve, reject) => {
      const request = indexedDB.open(DB_NAME, DB_VERSION);

      request.onupgradeneeded = (event) => {
        const database = event.target.result;
        if (!database.objectStoreNames.contains(STORE_NAME)) {
          database.createObjectStore(STORE_NAME, { keyPath: 'id' });
        }
      };

      request.onsuccess = (event) => {
        db = event.target.result;
        resolve(db);
      };

      request.onerror = (event) => {
        console.error('[keystore] Failed to open DB:', event.target.error);
        reject(event.target.error);
      };
    });
  }

  const khaaliKeystore = {

    /**
     * Store a group key.
     * @param {number|string} groupId — on-chain group ID
     * @param {string} keyHex — 64-char hex string (AES-256 key)
     * @param {string} walletAddress — owner's wallet address
     */
    async storeGroupKey(groupId, keyHex, walletAddress) {
      try {
        const database = await openDB();
        const tx = database.transaction(STORE_NAME, 'readwrite');
        const store = tx.objectStore(STORE_NAME);
        store.put({
          id: `group:${groupId}:${walletAddress.toLowerCase()}`,
          type: 'group_key',
          groupId: String(groupId),
          keyHex: keyHex,
          walletAddress: walletAddress.toLowerCase(),
          updatedAt: Date.now(),
        });
        await new Promise((resolve, reject) => {
          tx.oncomplete = resolve;
          tx.onerror = () => reject(tx.error);
        });
        console.log('[keystore] Stored group key for group', groupId);
      } catch (err) {
        console.error('[keystore] Failed to store group key:', err);
      }
    },

    /**
     * Retrieve a group key.
     * @param {number|string} groupId
     * @param {string} walletAddress
     * @returns {Promise<string|null>} — key hex or null
     */
    async getGroupKey(groupId, walletAddress) {
      try {
        const database = await openDB();
        const tx = database.transaction(STORE_NAME, 'readonly');
        const store = tx.objectStore(STORE_NAME);
        const id = `group:${groupId}:${walletAddress.toLowerCase()}`;

        return new Promise((resolve, reject) => {
          const request = store.get(id);
          request.onsuccess = () => {
            const result = request.result;
            resolve(result ? result.keyHex : null);
          };
          request.onerror = () => reject(request.error);
        });
      } catch (err) {
        console.error('[keystore] Failed to get group key:', err);
        return null;
      }
    },

    /**
     * Store a shared secret with another user.
     * @param {string} theirAddress — the other user's wallet address
     * @param {string} secretHex — shared secret hex
     * @param {string} myAddress — our wallet address
     */
    async storeSharedSecret(theirAddress, secretHex, myAddress) {
      try {
        const database = await openDB();
        const tx = database.transaction(STORE_NAME, 'readwrite');
        const store = tx.objectStore(STORE_NAME);
        store.put({
          id: `shared:${myAddress.toLowerCase()}:${theirAddress.toLowerCase()}`,
          type: 'shared_secret',
          theirAddress: theirAddress.toLowerCase(),
          myAddress: myAddress.toLowerCase(),
          secretHex: secretHex,
          updatedAt: Date.now(),
        });
        await new Promise((resolve, reject) => {
          tx.oncomplete = resolve;
          tx.onerror = () => reject(tx.error);
        });
      } catch (err) {
        console.error('[keystore] Failed to store shared secret:', err);
      }
    },

    /**
     * Retrieve a shared secret.
     * @param {string} theirAddress
     * @param {string} myAddress
     * @returns {Promise<string|null>}
     */
    async getSharedSecret(theirAddress, myAddress) {
      try {
        const database = await openDB();
        const tx = database.transaction(STORE_NAME, 'readonly');
        const store = tx.objectStore(STORE_NAME);
        const id = `shared:${myAddress.toLowerCase()}:${theirAddress.toLowerCase()}`;

        return new Promise((resolve, reject) => {
          const request = store.get(id);
          request.onsuccess = () => {
            const result = request.result;
            resolve(result ? result.secretHex : null);
          };
          request.onerror = () => reject(request.error);
        });
      } catch (err) {
        console.error('[keystore] Failed to get shared secret:', err);
        return null;
      }
    },

    /**
     * Delete all stored keys (logout cleanup).
     */
    async clearAll() {
      try {
        const database = await openDB();
        const tx = database.transaction(STORE_NAME, 'readwrite');
        const store = tx.objectStore(STORE_NAME);
        store.clear();
        await new Promise((resolve, reject) => {
          tx.oncomplete = resolve;
          tx.onerror = () => reject(tx.error);
        });
        console.log('[keystore] Cleared all keys');
      } catch (err) {
        console.error('[keystore] Failed to clear:', err);
      }
    },
  };

  window.khaaliKeystore = khaaliKeystore;
})();
