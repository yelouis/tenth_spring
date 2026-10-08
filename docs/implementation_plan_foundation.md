# Implementation Plan — Foundation (Phase 0 + Phase 1)

This document is a build-ready specification for the foundation of Tenth Spring: the companion's location-capture pipeline (Phase 0) and the PC project + pairing + sync + canonical data models (Phase 1). It is written so an implementing model can build it correctly **without** re-deriving design decisions, and can **validate** each component against explicit criteria.

**Scope discipline.** Only Phase 0 and Phase 1 are specified here. Later phases (world gen, travel, threats, expeditions, base, art) each get their own `implementation_plan_*.md` when reached — do not build ahead of the foundation. Every rule below traces to a `design_*.md` contract; where this doc and a design doc disagree, the design doc wins and you file the conflict in `ongoing_general_errors.md`.

**Stack (Decision 1).** PC = Godot 4 (GDScript). Companion = Flutter (Dart). Storage = SQLite both sides (Drift on Flutter; the vendored `godot-sqlite` v4.4 GDExtension on Godot — Decision 7). Sync = LAN-only TLS with a pinned self-signed certificate (Decision 11). D3 (geolocation plugin) is code-complete pending its device soak; D4 is superseded by Decision 11.

**Golden invariants (enforce in code review on every foundation PR).**
1. **Cartography, never cargo** — the sync ingest (§B4.5) may write only `map_cell`, `place_node`, `visit_log`, and the transient `bodyFix`. It must have *no* path to `inventory_item` / `base_state` — or, after the Pokémon pivot (2026-10-07), to the bag, party, PC box, or Pokémon tables. Assert this with a test (§B6).
2. **Raw coordinates never persist and never transit** — full-precision fixes exist only in volatile memory inside the capture pipeline; everything written to disk or sent over the wire is fuzzed (§A4).
3. **Idempotent sync** — replaying any batch changes nothing (§B4.4).
4. **No gameplay on the phone** — the companion contains capture + read-only map + sync only.

---

# Part A — Companion: Location Capture (Phase 0)

Goal: carrying the phone through a normal day produces a correct, fuzzed visit/corridor log at < 3%/day battery, with a GPX replay path for testing. No map reveal happens on the phone.

## A1. Project setup & permissions

Create the Flutter app under `companion/`. Packages (initial): `drift` + `sqlite3_flutter_libs` (outbox DB), `flutter_secure_storage` (private keys — never in the DB), `mobile_scanner` (QR pairing, used in Phase 1), a geolocation package per Decision 3, and `xml` (GPX parsing).

Permissions and platform config:
- **iOS** (`Info.plist`): `NSLocationWhenInUseUsageDescription` and `NSLocationAlwaysAndWhenInUseUsageDescription` — copy is the canonical rationale from `design_privacy_and_location.md` §3, verbatim. Add `UIBackgroundModes` = `location`.
- **Android** (`AndroidManifest.xml`): `ACCESS_COARSE_LOCATION`, `ACCESS_FINE_LOCATION`, `ACCESS_BACKGROUND_LOCATION` (API 29+), `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION` (API 34+), `POST_NOTIFICATIONS` (API 33+). Background capture runs in a foreground service with a low-priority persistent notification.
- **Staged runtime request** (required Android 11+, good practice iOS): request foreground ("While Using") first; only after the user has seen the fantasy and the rationale, request background ("Always") as a *separate* step. Declining "Always" must still leave a working app (foreground + manual "scout here").

Validation A1: on a clean install of each OS, verify the rationale strings render, the staged flow works, and denying background does not crash or dead-end (manual, both platforms + one Android 11+ device).

## A2. Location source abstraction (the seam GPX and tests plug into)

All capture consumes an interface, never the OS directly:

```dart
class Fix { double lat, lon, accuracyM; int tsUtcMs; double? speedMps; }   // full precision, in-memory only
abstract class LocationSource {
  Future<void> start();
  Future<void> stop();
  Stream<Fix> fixes();                 // raw timestamped fixes
  Stream<OsVisit>? nativeVisits();     // optional OS visit events (iOS CLVisit); null on Android
}
```

Implementations: `OsLocationSource` (Decision 3) and `GpxReplaySource` (§A8). The visit/corridor detector, fuzzer, and outbox all depend on `LocationSource` — so every test and the GPX harness inject a source with zero production-code changes.

Validation A2: unit test that a fake `LocationSource` emitting a scripted `Stream<Fix>` drives the whole pipeline; no code under test imports a geolocation package directly (enforce via a lint/grep test).

## A3. Visit & corridor detection

Runs on **full-precision fixes in memory**. Emits fuzzed results only (§A4). Constants from `game/config/tuning` mirrored into companion config: `visitRadiusMeters=75`, `visitDwellSeconds=120`, `corridorRevealMeters=60`, plus `maxAccuracyM=100`, `corridorSampleMeters=25`.

Algorithm (clustering, platform-agnostic; use `nativeVisits()` as a corroborating hint when present):
```
onFix(fix):
  if fix.accuracyM > maxAccuracyM: return          // drop noisy fixes
  if cluster == null: cluster = newCluster(fix); return
  if haversine(fix, cluster.centroid) <= visitRadiusMeters:
      cluster.add(fix)                              // running-mean centroid, extend lastTs
  else:
      if cluster.durationSeconds >= visitDwellSeconds:
          emitVisit(fuzzPoint(cluster.centroid), cluster.startTs, cluster.durationSeconds)
      emitCorridorSegment(cluster.lastFix, fix)     // the movement between dwells
      cluster = newCluster(fix)

onStationaryTimeout / onStop:
  if cluster.durationSeconds >= visitDwellSeconds and not emitted: emit arrival visit
```
- `emitCorridorSegment` resamples the polyline every `corridorSampleMeters` and writes each fuzzed point as a `corridor` outbox row (keeps rows bounded and privacy coarse). Road map-matching is a later refinement — do not attempt in Phase 0.
- Place identity is resolved **on the PC** (OSM lives there). The companion stores only fuzzed points; `placeId` is null on the phone.

Validation A3 (unit, deterministic): feed synthetic fix streams and assert emitted visits/corridors:
- dwell of 119 s → no visit; 121 s → one visit at the centroid.
- fixes with accuracy 150 m are ignored and don't break clustering.
- a straight 300 m walk between two dwells yields ~12 corridor points and exactly two visits.
- GPS jitter within 75 m during a dwell stays one visit (no false split).

## A4. Fuzzing — the only place raw coordinates exist on their way out

Single reviewed file `companion/lib/capture/fuzz.dart`. Nothing full-precision is ever written to Drift or handed to sync; fuzzing happens at the boundary between the in-memory detector and storage.

```dart
LatLon fuzzPoint(LatLon raw) => LatLon(_round(raw.lat, 3), _round(raw.lon, 3)); // ~110 m
// Home: never store the raw point. Snap to a homeFuzzMeters (300 m) grid and keep the cell only.
HomeCell fuzzHome(LatLon raw) => _gridCell(raw, homeFuzzMeters);
```

Validation A4 (unit): `fuzzPoint` is deterministic and idempotent (`fuzzPoint(fuzzPoint(x)) == fuzzPoint(x)`), never emits > 3 decimals; `fuzzHome` maps all raw points within a 300 m cell to the same cell id. Static test: grep asserts no file outside `fuzz.dart` references a `Fix.lat/lon` beyond the detector module.

## A5. Outbox storage (Drift)

```sql
CREATE TABLE visit_outbox (
  seq            INTEGER PRIMARY KEY AUTOINCREMENT,
  kind           TEXT NOT NULL CHECK (kind IN ('visit','corridor')),
  lat            REAL NOT NULL,      -- fuzzed
  lon            REAL NOT NULL,      -- fuzzed
  started_at     INTEGER NOT NULL,  -- UTC ms
  dwell_seconds  INTEGER,           -- visits only
  synced         INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL); -- schema_version, etc.
-- pairing table added in Phase 1 (§B3). Private keys go in flutter_secure_storage, NOT here.
```
`seq` is the monotonic sync cursor. Rows are retained until the PC acks them (§B4.4), then deleted.

Validation A5: schema round-trip test; `seq` strictly increases; a fixture DB migrates forward without data loss (§B6 framework, shared).

## A6. Scout ledger UI

Read-only. Groups today's `visit_outbox` rows and shows **names-free** entries — the phone has no OSM, and the reveal is reserved for the PC:
- Header: "3 places scouted today · sync at your PC to add them to the map."
- Rows: time + a coarse label ("a place near you", or a reverse-geocoded neighborhood at most). Never a POI name, never a map reveal.
- A "scout here" button (manual visit for "While Using"-only users) and a "pause scouting" toggle.

Validation A6: widget test that the ledger renders from a seeded outbox and that no map/fog widget exists in the companion widget tree (guards invariant 4).

## A7. Battery strategy

- Use SLC/motion-gated capture: GPS powers up on motion, stands down when stationary; rely on OS visit APIs where available (iOS). Never poll continuous high-accuracy.
- Android: persistent foreground service; batch DB writes; coalesce corridor points.
- Ship a hidden battery-debug log (fix counts, GPS-on duration) for the Phase 0 exit measurement.

Validation A7 (device, gating): 8–48 h real carry; battery attribution < 3%/day via iOS Energy Log and Android Battery Historian. Confirm capture survives app backgrounding and process death (Android foreground service restarts).

## A8. GPX replay harness (Decision 2)

Debug-builds only. `GpxReplaySource implements LocationSource`: parses a `.gpx`, emits each `<trkpt>` as a `Fix` (lat/lon/time; synthesize accuracy). Supports `timeScale` (e.g. 60× → a day in ~24 min) and an `instant` mode for unit/integration runs. Exposed only via a dev menu / `--dart-define`; compile-excluded from release (behind `kDebugMode` or a `dev` flavor).

Ship fixtures under `companion/test/fixtures/`: `errand_day.gpx` (2 dwells + connecting corridors), `commute.gpx` (long corridor, no dwell), `relocation_200mi.gpx` (home → distant city, for the stranded journey).

Validation A8: for each fixture, `GpxReplaySource` → detector → outbox yields the asserted visit/corridor rows (this is the backbone of the Phase 0 integration test and E2E journeys 1–5).

## Phase 0 exit criterion (must demonstrably pass)
Carry the phone a normal day (or replay `errand_day.gpx`) → the companion ledger lists the day's visits, the outbox holds the expected fuzzed visit + corridor rows, and real-device battery attribution is < 3%/day. No coordinate finer than 3 decimals exists on disk.

---

# Part B — PC + Pairing + Sync + Models (Phase 1)

Goal: stand up the Godot project and canonical DB, pair a phone, and prove a day of real scouting lands as `visit_log` rows + `known` fog cells on the PC after one LAN sync — idempotently and encrypted.

## B1. Godot project skeleton

Godot 4.3 under `game/`, GDScript. SQLite via `godot-sqlite` v4.4 (2shady4u, MIT), vendored under `game/addons/godot-sqlite/` (Decision 7). Autoload singletons:
- `Config` — loads `game/config/tuning` (all constants; single source of truth).
- `DB` — opens the SQLite file, runs migrations (§B6), exposes typed queries.
- `SyncServer` — TLS listener on TCP 7350 (§B4).
- `WorldClock` — created here but only ticked from Phase 3; Phase 1 just persists the row.

Validation B1: headless Godot test scene opens the DB, runs migrations to current version, and reports schema_version.

## B2. Canonical schemas (SQLite DDL)

The PC DB is the canonical world (companion holds only the outbox). Field semantics are defined in `design_game_state_and_models.md`; enums are stored as documented integer codes. Core tables for Phase 1 (later phases add columns via migrations, never by editing this DDL in place):

```sql
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);        -- schema_version

CREATE TABLE world_clock (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  game_epoch_minutes INTEGER NOT NULL DEFAULT 0,
  last_wall_sync INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE map_cell (
  cell_x INTEGER NOT NULL, cell_y INTEGER NOT NULL,
  reveal_state INTEGER NOT NULL DEFAULT 0,   -- 0 unknown, 1 known, 2 cleared
  tile_blob BLOB,                            -- regenerable cache, not source of truth
  first_revealed_at INTEGER,
  cell_seed INTEGER NOT NULL,
  PRIMARY KEY (cell_x, cell_y)
);

CREATE TABLE place_node (
  id TEXT PRIMARY KEY,                       -- stable hash of OSM id (or synthesized ruin)
  name TEXT, category INTEGER NOT NULL,      -- PlaceCategory code
  cell_x INTEGER, cell_y INTEGER, tile_x INTEGER, tile_y INTEGER,
  reveal_state INTEGER NOT NULL DEFAULT 1,
  visit_count INTEGER NOT NULL DEFAULT 0,
  last_real_visit_at INTEGER,
  loot_state INTEGER NOT NULL DEFAULT 0,     -- untouched/partial/stripped/regrown
  danger_tier INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE visit_log (                     -- canonical, mirrored from the phone outbox
  seq INTEGER NOT NULL, peer_id TEXT NOT NULL,
  place_id TEXT, lat REAL, lon REAL, started_at INTEGER, dwell_seconds INTEGER,
  kind TEXT NOT NULL,
  PRIMARY KEY (peer_id, seq)                 -- (peer, seq) is the idempotency key
);

CREATE TABLE sync_peer (
  peer_id TEXT PRIMARY KEY,
  device_token_hash BLOB,                    -- SHA-256 of the phone's device token (§B3); NULL = unpaired
  last_applied_seq INTEGER NOT NULL DEFAULT 0,
  last_body_lat REAL, last_body_lon REAL, last_body_ts INTEGER
);

CREATE TABLE player_profile (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  trainer_name TEXT, sprite_index INTEGER DEFAULT 0,
  pos_tile_x INTEGER, pos_tile_y INTEGER
);

CREATE TABLE base_state (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  home_cell_x INTEGER, home_cell_y INTEGER   -- fuzzed cell only; never raw home
);

CREATE TABLE osm_cache (
  cell_x INTEGER, cell_y INTEGER, fetched_at INTEGER, payload BLOB,
  PRIMARY KEY (cell_x, cell_y)
);
-- NOTE (2026-10-08, F23 + Decision 11): this v1 DDL was corrected in place ONCE — sync_peer.peer_pubkey ->
-- device_token_hash, zombie-era player_profile fields removed, inventory_item dropped (the bag arrives
-- by migration). That was safe only because no SQLite file had ever been created by any build. From
-- the first SQLite release on, this DDL is frozen: every change is a §B6 migration.
-- NOTE (2026-10-07 Pokémon pivot): colony_state/fortification/vehicle/death_cache are superseded by
-- haunt_zone / pc_box / bag_cache / pokemon tables, added by later-phase migrations — do not create them here.
-- (original note:) colony_state, fortification, vehicle, death_cache: created here as empty tables per the
-- models doc so migrations start clean, but exercised only from later phases.
```

Validation B2: per-table insert/read round-trip; enum code↔name mapping test; `(peer_id, seq)` uniqueness rejects duplicates.

## B3. Pairing (pinned TLS certificate + QR) — Decision 11

One PC ↔ one phone (v1.0). **Godot's built-in TLS on the PC, Dart's `SecureSocket` on the phone. No libsodium, no custom crypto.**

**PC identity** — created on first launch if absent (`game/sync/pc_identity.gd`):
1. `var key := Crypto.new().generate_rsa(2048)`.
2. `var cert := Crypto.new().generate_self_signed_certificate(key, "CN=tenthspring-pc,O=Tenth Spring,C=US", <now as YYYYMMDDhhmmss>, <now + 20 years>)`.
3. `pcId` = 16 bytes from `Crypto.generate_random_bytes`, hex-encoded (32 chars).
4. Save `key` to `user://sync_identity/pc.key` (`CryptoKey.save`) and `cert` to `user://sync_identity/pc.crt` (`X509Certificate.save`), with `pcId` in `user://sync_identity/pc_id.txt`.
   - **Never in the save DB, never in the repo.**
   - The directory is configurable exactly like `DB.configure_paths`, and tests use `user://test/sync_identity/`.
5. **Fingerprint** = SHA-256 over the certificate's **DER** bytes, as 64 lowercase hex chars. Godot 4.3's `X509Certificate` exposes only PEM (`save_to_string()`), so: drop the `-----BEGIN/END CERTIFICATE-----` lines, strip whitespace, `Marshalls.base64_to_raw()` → DER, then hash with `HashingContext` (`HASH_SHA256`).

**Pairing flow:**
1. The PC's pairing screen creates a **pairing code**: 16 random bytes, hex. Only one is active at a time; it expires after **10 minutes** or one successful pairing, whichever comes first.
2. The QR encodes compact JSON:

   `{"v":2,"pcId":"<32 hex>","fp":"<64 hex>","addrs":["192.168.1.20"],"port":7350,"pair":"<32 hex>"}`

   `addrs` = `IP.get_local_addresses()`, filtered as follows:
   - **keep** private IPv4 only (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`);
   - **drop** loopback and `169.254.0.0/16`;
   - **at most 4**.
3. The phone (`mobile_scanner`) parses it and rejects `v != 2`.
   - If it is already paired with **this** `pcId` **and** `fp`, it only updates the stored `addrs`/`port`. Done; no PAIR is sent.
   - Otherwise it generates:
     - `phoneId` once, if absent: 16 random bytes, hex;
     - a `deviceToken`: 32 bytes from `Random.secure()`.
4. The phone connects (§B4.2) and sends `PAIR`.
5. The PC checks `pair` against the active code with `Crypto.constant_time_compare`.
   - **On success:** store `sync_peer(peer_id = phoneId, device_token_hash = SHA-256(deviceToken))`, clear `device_token_hash` on any **other** peer row (its `visit_log` history stays), invalidate the code, and reply `PAIR_OK`.
   - **On failure:** reply `ERROR {code:"bad_pair_code"}` and close.
6. The phone stores `pcId`, `fp`, `addrs`, `port`, `phoneId`, and `deviceToken` in `flutter_secure_storage` only, never in the Drift DB.

Optional hardening, not a blocker: show the first 8 hex chars of `fp` on both screens for the user to compare.

Validation B3:
- **Fingerprint parity.** A committed test certificate (`game/tests/fixtures/test_cert.pem` and `companion/test/fixtures/test_cert.pem` — certificate only, **no private key**) yields the **same** fingerprint hex in GDScript and in Dart. Both must equal the value the committing agent computed with `openssl x509 -in test_cert.pem -outform der | shasum -a 256`.
- **Pairing code rules.** An expired code and a wrong code are both rejected; a used code cannot pair twice.
- **No secrets in the DB.** Neither the device token nor the private key appears in any DB file — assert by scanning the bytes.

## B4. Sync transport

### B4.1 Finding the PC (no mDNS in v1 — F27)
The PC listens on TCP **7350** on all interfaces.

**The phone tries, in order:**
1. the last address that synced successfully;
2. then each QR `addrs` entry.

Each attempt has a **3 s** connect timeout. If all fail, the phone shows a "can't reach your PC — open the scout report on your PC and re-scan its code" message, in scout vocabulary per §4 of the design doc. mDNS is deferred: Godot has no responder, and raw multicast needs Apple's restricted entitlement on iPhones.

**Platform requirements:**
- **iOS:** `NSLocalNetworkUsageDescription` in `Info.plist`.
- **Android:** `android.permission.INTERNET` in the **main** manifest. Flutter adds it only to debug builds.

### B4.2 Encrypted channel (TLS, pinned)
**Phone:**
- Call `SecureSocket.connect(host, port, context: SecurityContext(withTrustedRoots: false), onBadCertificate: (c) => hex(sha256(c.der)) == storedFp, timeout: 3s)`.
- `withTrustedRoots: false` is load-bearing. With it, *every* certificate fails normal verification, so every connection goes through the pin check. Without it, a certificate that chains to a public CA would skip `onBadCertificate` entirely.
- After connecting, re-check `socket.peerCertificate` against the pin, and destroy the socket on mismatch.

**PC:**
- `TCPServer.take_connection()` → `StreamPeerTLS.new()` → `accept_stream(tcp, TLSOptions.server(key, cert))`.
- Then `poll()` every frame until `get_status() == STATUS_CONNECTED`.
- If that takes more than **10 s**, or the status reaches `STATUS_ERROR`, close.

**Both sides:**
- **One session at a time.** A second connection during an active session is closed immediately.
- **Idle timeout: 30 s** without a complete frame, then close.

### B4.3 Frames and messages (plaintext shapes, inside TLS)
**Frame:**
- A 4-byte big-endian unsigned length **N**, then **N** bytes of UTF-8 JSON (one object with a `type` field).
- **1 ≤ N ≤ 1,048,576.** Anything else is a protocol error, and the connection closes.
- Frames may arrive split across reads or several per read. Buffer, never assume one frame per read.
```
PAIR      { type, v:2, phoneId, pair, deviceToken }                     // base64 token; first contact only
PAIR_OK   { type, pcId }
HELLO     { type, peerId, schemaVersion, deviceToken }                  // every session
HELLO_OK  { type, pcId, lastAppliedSeq }
BATCH     { type, rows: [ {seq, kind, lat, lon, startedAt, dwellSeconds?} ...],   // ≤ 500 rows, seq-ascending
            bodyFix: { lat, lon, tsUtcMs } }                                       // fuzzed
ACK       { type:"ACK", status:"ack", lastAppliedSeq, appliedCount }    // = process_batch()'s result + type
ERROR     { type, code }  // bad_pair_code | unpaired | schema_mismatch | protocol | busy
```
**HELLO checks** (the PC rejects with `ERROR` and closes):
- **Token:** the PC compares SHA-256(`deviceToken`) with the stored hash using `Crypto.constant_time_compare`; a mismatch → `unpaired`.
- **Schema:** a version mismatch → `schema_mismatch`. The phone then surfaces an "update one device" message. Never apply across incompatible schemas.

**BATCH is accepted only after a successful HELLO.** The phone sends BATCHes until its outbox is empty, then closes.

### B4.4 Idempotent apply (the core correctness property)
On `BATCH`, inside one DB transaction:
1. Read `sync_peer.last_applied_seq` for this peer.
2. Apply only rows with `seq > last_applied_seq`, in ascending order (§B4.5).
3. Set `last_applied_seq = max(applied seq)`; store `bodyFix` into `sync_peer.last_body_*`.
4. Reply `ACK { lastAppliedSeq }`.
Phone: on ACK, delete outbox rows with `seq <= lastAppliedSeq`. If the connection drops before ACK, nothing is deleted and nothing is half-applied (the transaction either commits fully or not); the phone resends from `last_acked` and the PC re-applies safely because rows `<= last_applied_seq` are skipped.

### B4.5 Applying a visit/corridor row → map reveal (**map tables only**)
For each row (ingest has write access to `map_cell`, `place_node`, `visit_log` only):
- Append the canonical `visit_log` row (`peer_id, seq, ...`).
- Reveal the `map_cell(s)` containing the point → `reveal_state = known` if currently `unknown`; stamp `first_revealed_at`.
- `visit` rows: find the nearest POI in `osm_cache` within `visitRadiusMeters`. If found → upsert `place_node` (`visit_count += 1`, update `last_real_visit_at`, set `reveal_state = known` if unknown). If the cell's OSM isn't cached yet → mark the cell `known`, enqueue an Overpass fetch for that cell, and resolve `place_node` when it returns (deferred; the "intel ceremony" plays over this in Phase 2).
- `corridor` rows: reveal cells within `corridorRevealMeters` of the point as `known` terrain.

### B4.6 bodyFix & relocation handoff
`bodyFix` is retained on `sync_peer` for the session-start relocation in §B5. It is the phone's current fuzzed position — the anchor for fast travel.

Validation B4:
- Idempotency (unit): apply a fixture BATCH → assert map_cells/place_nodes/visit_log; **re-apply the identical BATCH → zero changes**; apply an out-of-order/overlapping BATCH → only new seqs land.
- Resumption (integration): kill the socket mid-batch (before ACK) → reconnect → final DB state equals the clean-run state exactly.
- Channel (integration, loopback): the phone accepts only the pinned certificate; a different self-signed certificate is refused before any frame is sent; a wrong device token gets `ERROR unpaired`; a 2 MiB frame header closes the connection.
- Isolation (unit, guards invariant 1): a BATCH whose handler is (in a fault-injection test) pointed at `inventory_item` fails a static capability check — the ingest module must not import/reference inventory tables at all.

## B5. Relocation on session start (fast travel = the phone)

On PC game launch:
1. `SyncServer` attempts discovery + a fresh sync. On success, use the just-synced `bodyFix`; on failure, use `sync_peer.last_body_*` and show the "scout out of contact" banner (`design_travel_and_time.md` §4).
2. Convert `bodyFix` lat/lon → global tile coords (same projection as `map_cell`). Find the nearest **revealed, traversable** tile via BFS over revealed cells; place `player_profile.pos`. If the area is `unknown`, reveal a minimal `corridorRevealMeters` circle so there is ground to stand on.
3. Compute distance from `bodyFix` to `base_state.home_cell` → set the stranded flag (gates stash access; `design_travel_and_time.md` §5). Show the distance-from-home banner.

Validation B5: with a seeded map + a synced bodyFix, the survivor spawns on the expected tile; with the peer unreachable, spawn uses the last body position + banner; a bodyFix far from home sets stranded and blocks stash reads (assert the stash query refuses).

## B6. Migration framework (both DBs)

`meta.schema_version`; on startup run ordered, idempotent migration steps when `version < current`. Each migration ships with a fixture DB at the prior version and a test asserting a lossless upgrade — **`visit_log` and `map_cell` are never dropped or rewritten destructively** (location history is unrecoverable). Add a capability/lint test that fails if the sync-ingest module gains a reference to `inventory_item`/`base_state` (invariant 1, permanent guard).

## Phase 1 exit criterion (must demonstrably pass)
A day of real scouting on a paired phone appears — after one LAN sync — as `visit_log` rows plus `known` `map_cell`s (and resolved `place_node`s where OSM is cached) in the PC DB. Re-running the same sync is a no-op. On the wire, payloads are ciphertext with no coordinate finer than 3 decimals.

---

# Validation summary (what "done" means for the foundation)

| Layer | How to validate |
|---|---|
| Companion unit | fuzz determinism/precision; visit detector on synthetic streams; GPX parse |
| Companion integration | each GPX fixture → expected outbox rows |
| Companion device (gate) | < 3%/day battery; background survives process death; staged permissions |
| PC unit | schema round-trip; enum mapping; **idempotent apply**; certificate-fingerprint parity; frame codec; ingest-isolation |
| Cross-device integration | pair → sync a fixture batch over loopback → expected PC state; replay = no-op; mid-batch drop resumes clean |
| Cross-device manual (gate) | real phone + PC on one WiFi: QR pair, real sync, re-scan after an address change; Wireshark shows only TLS records, no plaintext JSON or coords; relocation + out-of-contact fallback behave |

CI runs everything except the two device gates, which are manual pre-merge checks for any PR touching capture, battery, or the sync channel (agent guide, THE LOOP).

**Godot test harness contract (added 2026-10-08 after F25).** `godot -s` only runs scripts inheriting `SceneTree`/`MainLoop`, so game tests run as a **scene**: `game/tests/test_main.tscn` with a root `Node` script that, in `_ready()`, instantiates each test script, calls its `run_test()`, prints exactly one `PASS <name>` or `FAIL <name>` line per test, then calls `get_tree().quit(0 if all passed else 1)`. Running as a normal scene means autoloads (`DB`, `Config`, `SyncServer`) load exactly as in the game. The runner invokes `godot --headless --path game res://tests/test_main.tscn` and is green **only if** the exit code is 0 **and** the output contains one `PASS` line for every expected test — a crash before tests run, or an empty run, is a failure. A deliberately failing self-test (enabled by `TENTH_SPRING_HARNESS_SELFTEST=1`) must make the harness exit 1, proving it can fail. CI runs this with headless Godot **4.3-stable** (matching `project.godot`).
