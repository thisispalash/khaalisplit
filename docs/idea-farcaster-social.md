# Idea: Farcaster Social Graph for Friend Discovery

## The Problem

khaaliSplit's friend system is currently manual — users must know each other's addresses and explicitly send/accept friend requests on-chain. This works for existing friend groups, but there's no discovery mechanism. How do you find people you *should* be splitting expenses with?

## The Insight

Farcaster is an open social protocol where users have on-chain identities (FIDs) linked to Ethereum addresses. Farcaster's social graph — who follows whom, who interacts with whom — is **publicly readable** and maps directly to wallet addresses via verified on-chain claims.

If a user has both a Farcaster account and a khaaliSplit subname, we can suggest friends based on their existing social connections.

## How It Could Work

### Discovery Flow

1. **User links Farcaster**: During onboarding (or later in settings), the user connects their Farcaster FID. The app verifies the FID is linked to the same Ethereum address as their khaaliSplit subname.
2. **Fetch social graph**: The PWA queries Farcaster's hub (or a Neynar API) for the user's follows/followers.
3. **Cross-reference**: For each Farcaster connection, check if that address has a `*.khaalisplit.eth` subname registered (on-chain lookup via NameWrapper).
4. **Suggest friends**: Display matched users as "People you may want to split with" — showing their Farcaster profile (pfp, display name) alongside their khaaliSplit reputation score.
5. **One-tap friend request**: User taps to send a `requestFriend()` on-chain, with ECDH key exchange happening under the hood.

### Storing the Link

The Farcaster FID could be stored as an ENS text record on the user's subname:
- `text("com.khaalisplit.farcaster.fid")` → `"12345"`

This makes the link **publicly verifiable** — anyone can check that `alice.khaalisplit.eth` is linked to Farcaster FID 12345 and vice versa.

### Deeper Integrations

- **Farcaster Frames**: Build a Frame that lets users settle expenses or accept friend requests directly from their Farcaster feed
- **Channel-based groups**: Automatically suggest creating a khaaliSplit group for members of a Farcaster channel (e.g., a travel channel for a group trip)
- **Cast-based expenses**: "Split this dinner?" as a cast, with inline expense creation via Frames
- **Reputation cross-pollination**: Display khaaliSplit reputation scores on Farcaster profiles, giving social context to financial reliability

## Why This Is Interesting

- **Social graph bootstrapping** — instead of building a social network from scratch, piggyback on an existing decentralized one
- **Trust signal stacking** — Farcaster social proximity + khaaliSplit reputation score = stronger trust for new financial relationships
- **ENS as the glue** — Farcaster already resolves ENS names, khaaliSplit already uses ENS subnames. The identity layer is shared, so integration is natural.
- **Open protocol composability** — neither Farcaster nor khaaliSplit requires permission to read each other's data. The integration is purely additive.

## Trade-offs

- Farcaster adoption is still growing — not all khaaliSplit users will have Farcaster accounts
- Social graph != financial trust — someone you follow on Farcaster isn't necessarily someone you'd split rent with
- Privacy consideration — linking Farcaster FID to khaaliSplit subname makes the connection public and permanent (until the record is cleared)
- Requires off-chain infrastructure (Farcaster hub queries) that the current contract-only architecture doesn't need
