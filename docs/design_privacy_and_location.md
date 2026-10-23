# Privacy & Location

Location data is the game's fuel and its biggest liability. The pillar — **"your map is yours"** — is a product feature, not a compliance checkbox. These contracts bind every other system.

## 1. Data Contracts (non-negotiable)

- **One reading, on purpose, never kept** (Decision 29, 2026-10-21):
  - the phone reads your location **only** when you tap **Explore Here** or **Set home**, with "while using the app" permission;
  - the reading is looked up on the phone against the bundled places pack, then **discarded** — it is never stored, logged, or sent, at any precision;
  - there is no background location, no visit detection, and no route tracing.
- **Only area names leave the phone:** an explore event names a famous place and one of its areas (`place_id`, `area_key`); "Set home" names only the starter city. They travel one hop — phone → paired PC — over the direct, end-to-end-encrypted LAN channel (`design_companion_and_sync.md` §3). No account, no server, no cloud relay, no analytics.
- **Your home never leaves the phone,** not even fuzzed. The phone picks the nearest famous city itself, and the PC learns only that city.
- **Reveals are coarse by design:** the PC reveals whole neighbourhoods, cities, and parks — it never knows where inside them you stood.
- **No third-party SDKs** with location access, on either app.
- **Map data is fully offline** (Decisions 13, 23): the PC downloads pinned state files of OpenStreetMap and reads them locally; no map request ever names a place or area you've been. Only which state is ever revealed.
- **Export & erase:** both devices offer "export my map" (from the PC) and "erase everything" (the phone's outbox and pairing, plus the PC's world). Both are one tap, with no dark patterns.
- **Enforced separation:** the report ingest has no write path into the bag, party, PC box, or Pokémon tables (`design_resources_and_base.md` §5). Real-world exploring unlocks access, never cargo or creatures.

## 2. How a reading is taken
- **Permission:** "while using the app" only, asked the first time the player taps Explore Here, with the plain-language rationale in §3. "Always" is never requested; Android and iOS background modes are removed.
- **The reading:** `geolocator` `getCurrentPosition` at accuracy `high`, with a 10 s time limit. If the reported accuracy is worse than **100 m**, the app says `Your location is too fuzzy here — try again in the open.` and records nothing.
- **Battery:** one GPS reading per tap. There's nothing to budget.

## 3. Onboarding & Consent UX
- **The flow:** the PC's tutorial establishes the fantasy, then hands off to the companion install and QR pairing ("recruit your scout"). The phone explains its single permission at first use, in plain language:
  - **what it is:** one location reading when you tap a button;
  - **where it goes:** it's checked on your phone against a map of famous places, then thrown away;
  - **what leaves the phone:** only the name of the neighbourhood or park you unlocked, sent to your own PC;
  - **what it's never used for:** tracking, selling, ads, or resources.
- **Setting home** explains: `We use this once to find the famous city nearest you. Only the city's name is saved.`

## 4. Compliance Notes (verify before release)

- App Store / Play location-permission review guidelines require the in-app rationale to match actual behavior — the onboarding copy in §3 is the canonical rationale text.
- COPPA posture: 13+ rating; no location features gated for under-13 because the app is not directed at children (confirm with counsel).
- GDPR/CCPA posture: on-device-only architecture keeps us out of controller territory for location data; the export/erase controls in §1 are still implemented as if it applied (cheap goodwill).

## 5. Files
* `companion/lib/explore/explore_service.dart` — the one-shot reading, the pack lookup, and the immediate discard (the only place a coordinate exists, and only in memory).
* `companion/lib/screens/onboarding_consent.dart` — canonical rationale copy.
* `game/autoloads/sync_server.gd` (PC) — explore-event validation against the places pack; structurally no write access to the bag, party, PC box, or Pokémon tables.
