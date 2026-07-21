# Privacy & Location

Location data is the game's fuel and its biggest liability. The pillar — **"your map is yours"** — is a product feature, not a compliance checkbox. These contracts bind every other system.

## 1. Data Contracts (non-negotiable)

- **Your devices only**: raw GPS traces never leave the phone. Fuzzed `VisitLog` rows travel exactly one hop — phone → paired PC — over a direct, end-to-end-encrypted LAN channel (`design_companion_and_sync.md` §3). No account, no server, no cloud relay, no analytics containing coordinates. Steam Cloud (if enabled) may sync the *game save*; the save stores map state at fuzzed precision only.
- **Fuzzing at source**: coordinates are reduced to 3-decimal precision (~110 m) *on the phone before storage or sync* — higher precision never persists and never transits. The safehouse is stored only as a fuzzed cell (`homeFuzzMeters = 300` snap) — the exact home point never persists anywhere on either device.
- **No third-party SDKs** with location access, on either app. OSM Overpass queries (PC-side) are made for *cell-sized regions*, not points, and only for already-revealed cells (a query can't leak a precise position).
- **Export & erase**: settings on both devices expose "export my map" (GeoJSON, from the PC) and "erase everything" (wipes phone outbox + PC world + pairing). Both are one tap, no dark patterns.
- **Enforced separation**: the sync ingest has no write path into inventory/resource tables (see resources doc §5) — cartography, never cargo, at the architecture level.

## 2. Capture Strategy (battery + trust)

- Capture lives entirely in the **companion app**. Primary: OS significant-location-change + visit APIs (iOS `CLVisit`, Android fused provider with PASSIVE/BALANCED priority). Target battery cost < 3%/day.
- No continuous high-accuracy tracking, ever. Corridor traces come from SLC breadcrumbs interpolated along the road network, not from polling.
- Graceful degradation: with "While Using" permission only, the pipeline still works — visits are detected while the companion is open and a manual "scout here" button logs the current place. "Always" permission is the *enhancement*, never the wall.

## 3. Onboarding & Consent UX

- Flow: the PC game's tutorial establishes the fantasy first, then hands off to the companion install + QR pairing ("recruit your scout"). The permission ask happens on the phone at that moment, with a plain-language screen: what is collected, where it lives (your phone and your PC, nowhere else), what it's used for (drawing your map), and what it is never used for (selling, ads, resources).
- The safehouse is player-designated **on the PC** with an explicit "this stays fuzzy" note — we show the fuzz circle on the map so the promise is visible.
- Kill-switch: "pause scouting" one-tap toggle on the companion's main screen (and mirrored in the PC pause menu as a status indicator), no punishment attached.

## 4. Compliance Notes (verify before release)

- App Store / Play location-permission review guidelines require the in-app rationale to match actual behavior — the onboarding copy in §3 is the canonical rationale text.
- COPPA posture: 13+ rating; no location features gated for under-13 because the app is not directed at children (confirm with counsel).
- GDPR/CCPA posture: on-device-only architecture keeps us out of controller territory for location data; the export/erase controls in §1 are still implemented as if it applied (cheap goodwill).

## 5. Files
* `companion/lib/capture/capture_service.dart` — SLC/visit subscription, battery budget guards.
* `companion/lib/capture/fuzz.dart` — all precision-reduction in one reviewed file (the only place raw coordinates exist).
* `companion/lib/screens/onboarding_consent.dart` — canonical rationale copy.
* `game/sync/ingest` (PC) — visit-batch validation; structurally has no inventory write access.
