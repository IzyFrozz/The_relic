# Placeholder / temp assets to replace

Everything below is **stand-in art** (mostly the free *Pixel Crawler* pack + a few
"Meta data" sprites). The `Asset/Selected Icon/` folder is **your real icon pack** —
it is NOT a placeholder and is intentionally left out.

Replace by swapping the file at the same path (keep the filename to avoid re-wiring),
or by repointing the texture in the scene's Inspector.

---

## 1. Player
| Role | File |
|---|---|
| Hero sprite sheet (overworld + combat, 48×48) | `Asset/sprites/characters/player.png` |

The player is recolorable via a mask shader — see the `player-recolor-shader` memory
before swapping (the sheet's layout matters).

## 2. Enemies / mobs  → `Asset/Pixel Crawler - Free Pack/Entities/Mobs/`
Used by the 22 mob instances in `character.tscn` (levels 1–20). Each mob has an
**Idle-Sheet** and a **Death-Sheet**.
- **Orc Crew:** `Orc/`, `Orc - Rogue/`, `Orc - Shaman/`, `Orc - Warrior/`
- **Skeleton Crew:** `Skeleton - Base/`, `Skeleton - Mage/`, `Skeleton - Rogue/`, `Skeleton - Warrior/`

> If you want a **distinct enemy per level**, this is where to add sheets — the
> mob→level assignment lives in `character.tscn` (each `mobN` node's `enemy_level`).

## 3. NPCs
| In-game NPC | Placeholder file |
|---|---|
| Elder / Wizard (save point, "Create Your Hero") | `Asset/Pixel Crawler - Free Pack/Entities/Npc's/Wizzard/Idle/Idle-Sheet.png` |
| Fisherman & Navigator (Citizen) | `Asset/Pixel Crawler - Free Pack/Entities/Npc's/Citizen_F/Tavern_A/Idle/Idle_Side-Sheet.png` |
| Street Kid (quest giver) | `Asset/Meta data assets files/Visuals/CHARACTERS/npc/hood/poor-kid1.png` + `poor-kid2.png` |

## 4. Objects & props
| Object | Placeholder file |
|---|---|
| Ancient chest (closed/opened) | `Asset/Meta data assets files/Visuals/OBJECTS/sprites/chest-closed.png` (and `chest-opened.png`, referenced in `delivery_point.gd`) |
| World coin pickup | `Asset/Meta data assets files/Visuals/OBJECTS/coin/coin1.png` |
| Projectile / FX | `Asset/Meta data assets files/Visuals/FX/shot.png` |
| ItemsStation (anvil) | `Asset/Pixel Crawler - Free Pack/Environment/Structures/Stations/Anvil/Anvil only.png` (+ `Anvil.png`) |
| Signpost | uses `Asset/Selected Icon/help.png` (the "?" icon) as a stand-in — see `Sign.gd` |
| Fishing-spot marker | uses the fishing-rod icon (final) — not a placeholder |

## 5. World / tilemap  → `Asset/Pixel Crawler - Free Pack/Environment/`
The whole overworld & interiors are built from the free pack. **Do not edit
`map.tscn` / `foreground.tscn` directly** (project rule) — swap the source images:
- **Tilesets:** `Tilesets/` — `Water_tiles`, `Floors_Tiles`, `Wall_Tiles`, `Wall_Variations`, `Dungeon_Tiles`
- **Props:** `Props/Static/` — `Trees/` (Model_01–03), `Rocks`, `Vegetation`, `Furniture`, `Farm`, `Tools`, `Resources`, `Meat`, `Pan`, `Esoteric`, `Dungeon_Props`, `Shadows`
- **Buildings:** `Structures/Buildings/` — `Walls`, `Roofs`, `Floors`, `Props`, `Interior/`, `Shadows`
- **Stations:** `Structures/Stations/` — `Bonfire/`, `Sawmill/`, `Workbench/`, `Alchemy/`, `Anvil/`

## 6. Main-menu key art
Not a file yet — it's the text label **"🖼 Artwork Placeholder"** in
`main_menu.gd` (~line 111). Drop in real key art and replace that label with a
`TextureRect`.

---

## Audio (now handled by the SFX system)
The files in `Asset/Main Sound/` are also placeholders, but they're now wired as
**temporary slots in `sfx.tscn`** — replace them there via the Inspector (see
`SFX.gd`), not by hand-editing paths.
