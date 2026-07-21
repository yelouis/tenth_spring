# Companion App & Sync

This document defines the two-device architecture: what the phone companion does (and deliberately does not do), the pairing model, and the phone→PC sync protocol. The pillar: **the phone is the scout; the PC is the game.** The phone is also the survivor's *body* — its position at sync time is where each PC session begins.

## 1. Companion App Scope (deliberately thin)

The companion app contains **no gameplay**. Its entire feature set:

| Feature | Detail |
|---|---|
| **Location capture** | Background SLC/visit detection per `design_privacy_and_location.md` §2. This is the app's reason to exist. |
| **Scout ledger** | A running list of today's detected visits/corridors — *names only, no reveals*: "3 places scouted · sync at your PC to add them to the map." The fog-peel ceremony is reserved for PC. |
| **Memoir view** | Read-only rendered map of already-synced territory (the year-map). No fog updates until synced. |
| **Sync** | Pairing + transfer per §3. Shows last-sync time and pending-visit count. |
| **Controls** | Pause scouting toggle, export/erase, permission status. |

Explicitly **excluded** from the companion (v1.0): raids, inventory, base management, colony status, notifications about in-game events. If a feature makes the phone a place to *play*, it's out of scope — the phone's job is to make you look forward to the PC.

## 2. Pairing Model

- One PC install ↔ one phone (v1.0). Pairing: the PC shows a QR code encoding `{pcId, pubkey, LAN hint}`; the phone scans it; both derive a shared key (X25519 → symmetric session keys). The key never leaves the two devices.
- Re-pairing (new PC/phone) requires the old device or the erase flow — no account-based recovery, because there is no account.
- Multiple PCs (desktop + laptop) is a v1.1 question — filed as an open decision, not silently supported.

## 3. Sync Protocol

- **Transport**: direct LAN — phone discovers the paired PC via mDNS when both are on the same network; payloads are E2E-encrypted with the pairing key. No relay server exists in v1.0 (see §5 for the trade-off record).
- **Payload** (phone → PC): append-only batch of `VisitLog` rows since last ack + **`bodyFix`**: the phone's current fuzzed position + timestamp. Payloads are already fuzzed to storage precision — raw GPS never leaves the phone at any precision higher than the game consumes.
- **Ack** (PC → phone): last-applied sequence number + rendered map summary (for the memoir view). The PC never sends gameplay state to the phone beyond the map raster.
- **Idempotent + resumable**: sequence-numbered batches; replays are no-ops; a dead connection resumes mid-batch.
- **Session start**: on PC game launch, the game requests a fresh sync. `bodyFix` places the survivor (fast travel — `design_travel_and_time.md` §4). If the phone is unreachable, the session starts at the **last synced body position** with a "scout out of contact" banner — never blocked, never teleported home.

## 4. In-Fiction Framing

Sync is diegetic: the companion is the survivor's *field journal*, and syncing is "the scout reporting in." PC-side, new intel arrives as the map-table ceremony: fog peels, place chips stamp in, the day's route draws itself. This framing is a design contract, not flavor — UI copy on both sides uses scout/report/intel vocabulary, never "sync/upload/data."

## 5. Trade-offs Recorded

- **LAN-only sync** means new scouting appears only when phone and PC meet on one network. Accepted because gameplay happens at the PC, which is on that network; the laptop-travel case works via hotel Wi-Fi/hotspot. An optional E2E-encrypted relay is a v1.1 candidate if playtests show friction — it must preserve "server sees ciphertext only."
- **No account** means device loss loses unsynced scouting (synced map lives on PC; the PC save is the canonical world). Accepted: aligns with the no-account privacy stance.

## 6. Files
* Companion (Flutter): `companion/lib/capture/*`, `companion/lib/sync/pairing.dart`, `companion/lib/sync/transport.dart`, `companion/lib/screens/{ledger,memoir,settings}.dart`
* PC (Godot): `game/sync/sync_server.gd`, `game/sync/pairing.gd`, `game/world/intel_ceremony.gd`
