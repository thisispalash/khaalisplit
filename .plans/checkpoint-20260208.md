# Checkpoint — 2026-02-08

## Fixes Applied

1. **Wallet verify UI**: Added `as json` to Hyperscript fetch so `the result's ok` correctly reads the JSON `{ok: true}` response instead of checking a raw string.
2. **Nonce collisions**: Added thread-safe nonce manager to `send_tx()`. Rapid sequential calls (setAddr + setText x3 + setUserNode) no longer reuse the same nonce.
3. **Payment preferences**: Reads from local DB (`LinkedAddress` model) instead of on-chain `call_view()`. Instant, reliable. On-chain setText is fire-and-forget.
4. **createGroupFor placeholder**: Generates 32 random bytes instead of `0x00` when client doesn't provide encrypted key.

## Open Items / TBD

1. **wallet.js audit** — Needs a thorough review. Current state is ad hoc from rapid iteration. Signing flows, provider handling, and event listeners all need a pass.
2. **Nonce manager** — Thread-safe approach may be overkill for gunicorn sync workers. Evaluate if simpler `'pending'` nonce count is sufficient once RPC is stable.
3. **Data architecture pattern** — All reads should come from local DB or indexer (Hasura/Postgres), never from on-chain `call_view()`. On-chain writes are fire-and-forget. UI shows optimistic state with subtle pulse animation until indexer confirms. Indexer has its own stable RPC.
4. **RPC stability** — `ethpandaops.io` is unreliable. Configure Alchemy/Infura for backend writes. Indexer already has its own RPC.
5. **ECDH / encryption** — The group key encryption scheme needs revisiting. Current placeholder (random 32 bytes) works for DB/contract calls but the full ECDH flow in crypto.js (computeSharedSecret, HKDF, AES-GCM wrap) hasn't been validated end-to-end.
6. **Friend search UX** — Support search by address or display name, not just subname. Rate-limit or scope searches. Show current user in results but visually mark as "You".
7. **Group invite** — Returns 404 for non-existent subnames. Consider showing inline error instead of silent failure.
