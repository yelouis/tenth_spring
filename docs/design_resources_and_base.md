# Items, Bag & Home Safehouse

This document defines which items real places yield, the bag, the home safehouse (PC box, healing, berry garden), and travel items. The pillar: **real-world movement unlocks access, never cargo** — every item is found and every Pokémon is caught in play.

Items are referenced by **Gen 4 item index number** in repo data; names and icons come from the player's ROM (`design_rom_asset_pipeline.md` §5).

---

## 1. Place category → items found by searching

| PlaceCategory | OSM sources (examples) | Common finds | Rare finds |
|---|---|---|---|
| `medical` | pharmacy, clinic, dentist | Potion, Antidote, Paralyze Heal | Super Potion, Full Heal, Revive |
| `grocery` | supermarket, convenience, restaurant | Oran Berry, Pecha Berry, Chesto Berry | Sitrus Berry |
| `hardware` | hardware, department store, DIY | Poké Ball | Great Ball |
| `roadside` | fuel station, garage | Repel, Escape Rope | Super Repel |
| `civic` | school, library, office | Escape Rope | a TM |
| `bigbox` | mall, department store | mixed jackpot from all tables | Ultra Ball |
| `park` | park, forest, allotments | Berries | Leaf Stone |
| `haunted` | cemetery, ruins, hospital, abandoned buildings | **Dusk Ball**, Spell Tag | **Reaper Cloth, Dusk Stone**, Odd Keystone (unique, ruins only) |
| `landmark` | national park, monument, stadium | — (legendary site) | Ultra Ball, Max Revive |
| `ruin` | unmapped buildings | small mixed | — |
| `home` | player-designated | — (safehouse) | — |

- **Quality scales with distance tier and haunt stage:** each tier past 0–2 mi shifts one step up a table (Poké → Great → Ultra Ball; Potion → Super → Hyper Potion). Defeating a zone boss rolls the next tier up.
- Full item tables: `game/config/item_tables.json` (item index numbers + weights only).

## 2. The bag

Pockets as in Diamond/Pearl: Items, Medicine, Poké Balls, TMs & HMs, Berries, Key Items. Stacks up to 999. **No carry-weight limit** — the bag's risk is that it drops when you black out, not that it fills.

## 3. The home safehouse

- **PC box:** 18 boxes × 30 = 540 slots. Accessible only within `baseAccessMeters` of home (the stranded rule). Sealed by a stage-4 haunting adjacent to home until its boss is beaten (`design_encounters_and_haunted_zones.md` §5.4).
- **Full heal:** resting at home heals the whole party — the only place that can.
- **Berry garden:** plant berries in garden plots; they grow over game days (as in Diamond/Pearl). The **only renewable resource**, capped at 8 plots so exploring stays necessary.

## 4. Travel items

- **Bicycle** (unique key item, found at a `shop=bicycle` or `hardware` site): ×2 travel speed. Replaces the old vehicles-and-fuel system entirely — there is no fuel.
- **Escape Rope:** instantly leave a site interior to its entrance (not a teleport home — the only teleport remains your real body).

## 5. Economy contracts

- **No money, purchases, ads, or premium currency** — and given the IP model, no monetization of any kind (`design_rom_asset_pipeline.md` §9).
- **No item or Pokémon may be granted by a real-world event** — not steps, visits, or streaks. Real-world events can only *unlock access* (a revealed site, a landmark, a gated event that must still be won in play). Enforced architecturally: the sync ingest has no write path to the bag, party, or PC (golden invariant 1).

## 6. Files (PC game)
* `game/config/poi_mapping.gd` — OSM tag → PlaceCategory (single source of truth; includes `haunted`, `roadside`, `landmark`).
* `game/config/item_tables.json` — category × tier item weights.
* `game/home/pc_box.gd`, `game/home/garden.gd`, `game/inventory/bag.gd`.
