# Companion App & Sync

This document defines the two-device architecture: what the phone companion does (and deliberately does not do), the pairing model, and the phone→PC sync protocol. The pillar: **the phone is the scout; the PC is the game.** The phone is also the player's *body* — its position at sync time is where each PC session begins.

## 1. Companion App Scope (deliberately thin)

The companion app contains **no gameplay**. Its entire feature set:

| Feature | Detail |
|---|---|
| **Location capture** | Background SLC/visit detection per `design_privacy_and_location.md` §2. This is the app's reason to exist. |
| **Scout ledger** | A running list of today's detected visits/corridors — *names only, no reveals*: "3 places scouted · sync at your PC to add them to the map." The fog-peel ceremony is reserved for PC. |
| **Memoir view** | Read-only rendered map of already-synced territory (the year-map). No fog updates until synced. |
| **Sync** | Pairing + transfer per §3. Shows last-sync time and pending-visit count. |
| **Controls** | Pause scouting toggle, export/erase, permission status. |

Explicitly **excluded** from the companion (v1.0): battles, catching, the party, the bag, the PC box, haunting status, and notifications about in-game events. If a feature makes the phone a place to *play*, it's out of scope — the phone's job is to make you look forward to the PC.

**The companion contains no Nintendo assets or names — ever.** No Pokémon sprites, names, or Pokédex text, not even cached from the PC. The phone has no ROM, it must stay listable on the App Store and Google Play, and it is a location tracker, not a Pokémon app. Its memoir map shows terrain, places, and visit history only (`design_rom_asset_pipeline.md` §8).

## 2. Pairing Model

- **One PC install ↔ one phone (v1.0).** Pairing a new phone replaces the old one's credential. The old phone's synced history stays in the PC save, because location history is never deleted.
- **The PC has its own identity** (Decision 11): a self-signed TLS certificate, generated once on first launch and stored in the PC's user data folder. It is never stored in the save DB and never in the repo.
- **The pairing QR code** (shown on the PC) carries:
  - the PC's id;
  - the **SHA-256 fingerprint** of that certificate;
  - the PC's LAN addresses and port;
  - a one-time pairing code that expires after 10 minutes or one use.
- **When the phone scans it:**
  1. The phone connects over TLS and checks the fingerprint.
  2. It sends the pairing code plus a freshly generated 256-bit **device token**.
  3. The PC stores only the token's SHA-256 hash.
- **Trust model:** the phone trusts **no certificate authority** — only the fingerprint it scanned. The PC trusts only a phone that presents the token. No secret ever leaves the two devices. Scanning the QR in person is what defeats a man-in-the-middle.
- **Re-pairing** (new PC or phone) means scanning a new QR on the PC. There is no account-based recovery, because there is no account.
- **Multiple PCs** (desktop + laptop) is a v1.1 question, filed as an open decision rather than silently supported.

## 3. Sync Protocol

- **Transport: direct LAN TCP, wrapped in TLS**, using Godot's built-in TLS on the PC and Dart's `SecureSocket` on the phone. Messages are length-prefixed JSON frames inside the TLS stream. No relay server exists in v1.0 (see §5 for the trade-off record).
- **Finding the PC.** The phone tries the address that last worked, then the addresses from the pairing QR. If none answers — usually because the router gave the PC a new address — the phone asks the player to re-scan the QR on the PC. A re-scan from the same PC (same id and fingerprint) just updates the addresses, without re-pairing. **mDNS auto-discovery is deferred** (F27): Godot has no mDNS responder, and raw multicast from the phone needs a restricted Apple entitlement on iPhones.
- **Payload** (phone → PC): an append-only batch of `VisitLog` rows since the last ack, plus **`bodyFix`** — the phone's current fuzzed position and timestamp. Payloads are already fuzzed to storage precision; raw GPS never leaves the phone at any precision higher than the game consumes.
- **Ack** (PC → phone): the last-applied sequence number. A rendered map summary for the memoir view is added when the memoir view is built. The PC never sends gameplay state to the phone beyond the map raster.
- **Idempotent and resumable:** batches are sequence-numbered; replays are no-ops; a dead connection resumes from the last ack.
- **Session start:** on PC game launch, the game requests a fresh sync. `bodyFix` places the player (fast travel — `design_travel_and_time.md` §4). If the phone is unreachable, the session starts at the **last synced body position** with a "scout out of contact" banner — never blocked, never teleported home.
- Exact message shapes, frame limits, and timeouts: `implementation_plan_foundation.md` §B3–B4.

## 4. In-Fiction Framing

Sync is diegetic: the companion is the trainer's *field journal*, and syncing is "the scout reporting in." PC-side, new intel arrives as the map-table ceremony: fog peels, place chips stamp in, the day's route draws itself. This framing is a design contract, not flavor — UI copy on both sides uses scout/report/intel vocabulary, never "sync/upload/data."

## 5. Trade-offs Recorded

- **LAN-only sync** means new scouting appears only when phone and PC meet on one network. Accepted because gameplay happens at the PC, which is on that network; the laptop-travel case works via hotel Wi-Fi/hotspot. An optional E2E-encrypted relay is a v1.1 candidate if playtests show friction — it must preserve "server sees ciphertext only."
- **No account** means device loss loses unsynced scouting (synced map lives on PC; the PC save is the canonical world). Accepted: aligns with the no-account privacy stance.

## 6. Files
* Companion (Flutter): `companion/lib/capture/*`, `companion/lib/sync/pairing.dart`, `companion/lib/sync/transport.dart`, `companion/lib/screens/{ledger,memoir,settings}.dart`
* PC (Godot): `game/autoloads/sync_server.gd` (TLS listener, frames, dispatch), `game/sync/pc_identity.gd` (certificate + fingerprint), `game/sync/pairing.gd` (pairing codes, QR payload), `game/world/intel_ceremony.gd`
