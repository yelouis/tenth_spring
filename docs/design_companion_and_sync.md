# Companion App & Sync

This document defines the two-device architecture: what the phone companion does (and deliberately does not do), the pairing model, and the phone→PC report protocol. The pillar: **the phone is the scout; the PC is the game.** Since Decision 29 (2026-10-21) the phone no longer tracks anything. It answers one question when you ask it — *"is this somewhere new?"* — and carries the answer to the PC.

## 1. Companion App Scope (deliberately thin)

The companion app contains **no gameplay**. Its entire feature set:

| Feature | Detail |
|---|---|
| **Explore Here** | The big button on the main screen. One tap takes **one** location reading (permission "while using the app" only), looks it up in the bundled **places pack** (§1.1), shows the result immediately, and **discards the reading**. |
| **What Explore Here says** | New neighbourhood → `New neighbourhood — <name>, <city>!`. Already explored → `Already explored — <name>. <k> of <T> neighbourhoods explored in <city>.`. City threshold reached → also `City revealed — <city>! You can Distort there from home.`. Park → `<Park> revealed!`. Nowhere famous → `This spot isn't on Tenth Spring's map. The map covers 27 famous cities and 60 parks and wonders.` Fuzzy reading (accuracy worse than 100 m) → `Your location is too fuzzy here — try again in the open.` (no unlock). |
| **Explored list** | The places you've explored, grouped by city or park, with progress (`Boston — 2 of 2 neighbourhoods · revealed`). Names only. |
| **Set home** | One tap during setup (repeatable): one reading picks the **famous city nearest home** on the phone. **Only that city's id leaves the phone.** |
| **Report to PC** | Pairing, plus sending the pending explore events per §3. Shows the number waiting and the last report time. |
| **Controls** | Export/erase, permission status, and `© OpenStreetMap contributors` (the places pack is OpenStreetMap data). |

**Explicitly excluded:** background location (removed by Decision 29), push notifications, battles, catching, the party, the bag, the PC box, haunting status. If a feature makes the phone a place to *play*, it's out of scope.

**The companion contains no Nintendo assets or names — ever.** No Pokémon sprites, names, or Pokédex text. The places pack holds only public OpenStreetMap geography. The app must stay listable on the App Store and Google Play (`design_rom_asset_pipeline.md` §8).

### 1.1 The places pack
- A compact, read-only file bundled with **both** the companion and the PC game: `places_pack_v<N>.json.gz`. It's built once per map snapshot (`MAP_SNAPSHOT`) by `tools/build_places_pack.py` — `implementation_plan_explore_here.md` §1.
- **It holds:**
  - for each of the **27 cities**: its boundary, its neighbourhoods (real OpenStreetMap neighbourhood areas, else areas around named neighbourhood points, else ~1 km districts), each neighbourhood's cells, and the threshold `T`;
  - for each of the **60 parks and wonders**: its cells;
  - for every place: its Waypost position (to pick the starter city).
- **It's the single source of truth for areas.** The phone uses it to answer Explore Here, and the PC uses the identical file to apply unlocks and to fill its place stores' `area_cells`. The phone and the PC can't disagree.

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
- **A phone the PC no longer recognises re-pairs fully** (F33, 2026-10-09). When the PC answers `unpaired`, the phone discards its device token, keeping its phone id and the PC's id, fingerprint, and addresses. Its next scan of that PC's QR then performs a real pairing instead of only refreshing addresses.
- **Multiple PCs** (desktop + laptop) is a v1.1 question, filed as an open decision rather than silently supported.

## 3. Sync Protocol

- **Transport: direct LAN TCP, wrapped in TLS**, using Godot's built-in TLS on the PC and Dart's `SecureSocket` on the phone. Messages are length-prefixed JSON frames inside the TLS stream. No relay server exists in v1.0 (see §5 for the trade-off record).
- **Finding the PC.** The phone tries the address that last worked, then the addresses from the pairing QR. If none answers — usually because the router gave the PC a new address — the phone asks the player to re-scan the QR on the PC. A re-scan from the same PC (same id and fingerprint) just updates the addresses, without re-pairing. **mDNS auto-discovery is deferred** (F27): Godot has no mDNS responder, and raw multicast from the phone needs a restricted Apple entitlement on iPhones.
- **Payload** (phone → PC, since Decision 29): an append-only batch of **explore events** since the last ack. Each event is `{"seq", "kind": "explore", "place_id", "area_key", "tsUtcMs"}`, or `{"seq", "kind": "home", "starter_place_id", "tsUtcMs"}`. **No coordinates are ever sent** — not fuzzed, not rounded.
  - The phone also sends the places-pack version in `HELLO` (`packVersion`). A mismatch is answered `ERROR pack_mismatch`; the phone then shows `Your companion and game have different map versions — update both.`
- **The PC checks every event:** `place_id` and `area_key` must exist in its places pack, and `kind` must be `explore` or `home`. It stores each event as a `visit_log` row (`kind`, `place_id` = area key, `lat`/`lon` NULL — no schema change). The reveal engine then unlocks by the same rules the phone used (`design_famous_places.md` §3).
- **`bodyFix` is retired** (Decision 29). New phones never send it, and the PC ignores it if an old build does.
- **Ack** (PC → phone): the last-applied sequence number. The PC never sends gameplay state to the phone.
- **Idempotent and resumable:** batches are sequence-numbered, replays are no-ops, and a dead connection resumes from the last ack.
- **Session start:** a session starts **where the last one ended** — the hub, or the tile where you quit inside a place (`design_travel_and_time.md` §4). The phone never moves you. The PC asks for a report at launch, but never waits for one.
- Exact message shapes, frame limits, and timeouts: `implementation_plan_foundation.md` §B3–B4.

## 4. In-Fiction Framing

Reporting is diegetic: the companion is the Walker's *Ledger*, and Explore Here is "marking the ground you've walked". On the PC, new areas arrive as the map-table ceremony: fog peels back neighbourhood by neighbourhood, and a newly revealed city lights up on the Town Map. This framing is a design contract, not flavor — UI copy on both sides uses scout/report/intel vocabulary, never "sync/upload/data."

## 5. Trade-offs Recorded

- **LAN-only sync** means new scouting appears only when phone and PC meet on one network. Accepted because gameplay happens at the PC, which is on that network; the laptop-travel case works via hotel Wi-Fi/hotspot. An optional E2E-encrypted relay is a v1.1 candidate if playtests show friction — it must preserve "server sees ciphertext only."
- **No account** means device loss loses unsynced scouting (synced map lives on PC; the PC save is the canonical world). Accepted: aligns with the no-account privacy stance.

## 6. Files
* Companion (Flutter): `companion/lib/explore/*` (places pack, lookup, explore outbox), `companion/lib/sync/pairing.dart`, `companion/lib/sync/frame_codec.dart`, `companion/lib/sync/scout_link.dart`, `companion/lib/ui/*`. `companion/lib/capture/*` (background capture) is retired by Decision 29.
* Shared data: `game/data/places_pack_v<N>.json.gz`, copied byte-identically to `companion/assets/`.
* PC (Godot): `game/autoloads/sync_server.gd` (TLS listener, frames, dispatch), `game/sync/pc_identity.gd` (certificate + fingerprint), `game/sync/pairing.gd` (pairing codes, QR payload), `game/sync/frame_codec.gd`, `game/sync/qr_code.gd`, `game/scenes/pairing.tscn`
