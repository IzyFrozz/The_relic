# SESSION HANDOFF — The Relic (Godot 4.6 JRPG)

Drop this into the first message of the next session.

---

## 0. Snapshot
- **Branch:** `testingHeng`  ·  **HEAD:** `79468af3 v0.7.7`  ·  **working tree: CLEAN** (everything committed).
- **Engine:** Godot **4.6.1.stable**. Binary at `C:/Program Files/Godot/Godot.exe` (NOT on PATH — use the full path).
- **Do NOT commit or push unless the user explicitly asks.** When they do: branch is not `main`, so commit directly on `testingHeng`. End commit messages with the Co-Authored-By line.

## 1. What this project is
A top-down pixel JRPG. Overworld exploration + turn-based combat. Win condition: collect 10 coins → Street Kid gives a key → open chest → get the **Ancient Relic** → turn it in (with a keep-vs-turn-in choice) → post-game continues (enemies respawn, relic gone).
- **Tile grid is 16×16.** Character sprites are bigger (player 48×48, NPCs 32/64). New world art → target 16px tiles.
- Window 1920×1080, `canvas_items` stretch. Camera zoom ~6×, so small sprites render large.

## 2. Architecture (know this before editing)
**Scene composition:** `main.tscn` (root `main`) instances `map.tscn` (world tilemap), `character.tscn` (all mobs live here under node `Character`), `foreground.tscn`, `ui.tscn`, and builds the HUD via `OverworldHUD.gd`. Player is `mainplayer` (direct child of `main`). One shared world coordinate space.

**Autoloads** (`project.godot [autoload]`):
- `QuestManager` — all run state + save/load + item metadata (`ITEM_META`) + side-quest engine.
- `KeybindManager` — rebindable actions, persists to `user://keybinds.cfg`.
- `Toast`, `DialogueManager` (linear reader + `ask()` for yes/no choices), `PromptHUD`, `ScreenFade`.
- `WorldMap` — fog-of-war minimap + full map + compass (see §4).
- `IconDB` — emoji→texture icon system (see §5, the CURRENT focus).

**HARD RULES / gotchas:**
- **NEVER edit `map.tscn` or `foreground.tscn`.** Place new world objects in `main.tscn` only.
- **Player-recolor shader trap** (long-term memory): recolor is mask-driven; combat FX that set `sprite.modulate` toggle `recolor_on` off automatically in `mainplayer._process`. Don't fight it.
- **Off-island coords:** house interiors (`x ≈ -3000…-4900`) and the combat arena (battle markers `x ≈ -2971 / -1632`) live far off the island. `WorldMap.OVERWORLD_BOUNDS = Rect2(-1200,-900,2800,1900)` excludes them from the map.
- **NPC pattern:** simple NPCs are `Area2D` roots (SaveNPC, delivery_point, FishingSpot, quest_item). Some are now **`CharacterBody2D` + a child `Area2D`** for solid collision (NavigatorNPC, Sign) — they wire detection off `get_node("Area2D").body_entered/exited` in `_ready`.

## 3. Verification workflow (ALWAYS run after edits)
```bash
GODOT="/c/Program Files/Godot/Godot.exe"
# compile + import (also generates .uid for new scripts, imports new PNGs):
"$GODOT" --headless --editor --quit-after 400 2>&1 | grep -iE "SCRIPT ERROR|Parse Error|Compile Error|Failed to load"
# runtime (exercises autoload _ready — catches WorldMap/IconDB init errors):
"$GODOT" --headless --quit-after 120 2>&1 | grep -iE "SCRIPT ERROR|ERROR|null instance"
```
- `--headless --check-only --script X.gd` catches syntax errors but **false-positives on autoload identifiers** (QuestManager/IconDB "not found") — ignore those, trust only real `Parse Error`.
- Combat/fishing flows need live input → can't be driven headless; validate by logic review + ask the user to test.
- **Edit tab gotcha:** GDScript match-case labels are 2 tabs, bodies 3 tabs. If an Edit says "string not found", re-Read and count tabs.

## 4. Gameplay systems reworked (current behavior)
- **Combat items** (`MobEnemy.gd` + `QuestManager.ITEM_META`): all deal/heal in **multiples of 10**.
  - **Relic:** consumed on use (returns to crate pool); 40 unblockable dmg + 20 heal + cleanse; charges from damage traded **only while held** (not proactive); charge requirement climbs per use (`QuestManager.relic_uses`, base 100 +40/use). A relic kill ends combat immediately.
  - **Phoenix Feather:** passive **auto-revive only** (no manual use) to 40 HP, cooldown 5+ (climbs); on death plays die-beat → gold-flash → rise. Max 1 in bag.
  - **Mirror Clone** (replaced War Banner; from fishing): 70%-opacity blue double dashes **forward** (player stays put); strikes first for flat 20 then you hit; soaks the enemy's next hit (enemy runs to the clone) and shatters.
  - **Max-one items** (`MAX_ONE_ITEMS`): relic, phoenix — supply drops substitute if you already hold one.
  - **Golden-heart heal cap:** healing (player AND enemy) caps at 300 (red hearts); HP above 300 is an unhealable per-fight bonus; heal items gray out at cap. See `QuestManager.heal_player()` / `MobEnemy._enemy_heal()`.
  - Level-1 mobs carry **no items** (fast tutorial fight).
- **Save system (nested):** 3 **sessions** (menu) × 3 **save slots** each. Files `user://s{session}_{slot}.save`. New Game → customize → pick an EMPTY session (delete a full one to free). Load → session → save slot. In-game Elder save / pause Load show only the **current session's** 3 slots. Flee/death → `reload_current_save()` or `restart_fresh_run()` (keeps character+session, never a stale slot). API: `save_to_slot`, `load_from(session,slot)`, `start_new_session`, `session_occupied/level`, `delete_session`. **Old flat `savegame_slot*.save` are NOT read** (format change).
- **Map/compass (`WorldMap.gd`, `MapCanvas.gd`):** gated entirely behind `has_compass` (granted by NavigatorNPC). Mini-map bottom-right; full map on the **`toggle_map`** action (editable, default M); compass = faked top-center ribbon. In a house/combat → "🚫 Map Unavailable". Explored cells persist in save.
- **Fishing:** split — Fisherman (`FishermanNPC.gd`) only talks/teaches; **`FishingSpot.gd`** (puddle node in `main.tscn`) casts, with 3-2-1 countdown, editable **`fish_reel`** key, 6 fish tiers, NO coins.
- **Coins:** only the **10 world coins** (no fishing coins, no lifetime/farming). `coin_hoarder` quest removed.
- **Navigator + Sign:** auto-intro dropped; a **`🪧 Signpost`** (`Sign.gd`, now CharacterBody2D w/ placeholder Sprite2D) near spawn holds the how-to notes; Navigator grants compass+map. "Meet the Locals" = 3 NPCs (street_kid, navigator, wizard); talking before accepting counts retroactively (`accept_side_quest` seeds progress).

## 5. ⭐ CURRENT FOCUS: the icon system (emoji → real icons)
Replacing emoji with pixel icons from a pack (`Asset/Raven Fantasy Icons/…/Separated Files/64x64/fcN.png`; files are actually 32×32). Selected icons are copied+renamed into `Asset/Selected Icon/`.

**`IconDB.gd` (autoload):** maps a concept id → filename in `Asset/Selected Icon/`. `IconDB.tex("potion")` returns the Texture2D **or null** → callers fall back to emoji, so a partial set renders cleanly. Add mappings by editing `IconDB.MAP`.

**Naming convention in `Asset/Selected Icon/`:** singles named directly (`grindstone.png`, `key.png`). **Ranges** = rename the FIRST file, e.g. `fb265 (from here to fb272) is healing potion.png` then `fb266.png…fb272.png` are variations (small→large).

**WIRED (show real icons):**
- All 19 **combat items** in combat (`CombatUI.gd`) + loadout (`EquipmentMenu.gd`) — via `Button.icon` (`icon_max_width` 40-46), emoji stripped from text when an icon exists.
- **Stamina** state-icon under the player (`mainplayer.gd`) — single icon swapping green/yellow/red (`stamina_full/low/empty`).
- **Sign** placeholder sprite (`help.png` "?").

**NOT wired yet — the "wire the rest" pass** (mapped in IconDB but still emoji because they live in Label/RichText/Toast strings, not `Button.icon`):
- HUD **hearts** (HP bar is an emoji string via `QuestManager.hp_to_hearts`), **coin counter** (`OverworldHUD` quest tracker), **toasts** (crate/level-up/reward — `Toast.show_toast` takes a plain string; would need Toast to accept an icon), **menu buttons** (save/load/settings/menu in `main_menu`/`PauseMenu`), map/trophy/skull labels.
- User's trigger phrase: **"wire the rest"** → do these in ONE pass. RichTextLabel can use `[img]`; Labels/Toast need small structural changes (an icon TextureRect beside text, or extend `Toast.show_toast(text, icon_id)`).

**Confirmed mappings (from user):** quest log = `quest book.png`; talk-quest = `chat.png`; audio = `music node icon.png`; signpost = `help.png` (the `?`); loadout bag (🎒 in Roadmap) = `pouch.png`. The `sword/Armour icon (for profile)` files are **reserved for a future player-profile screen** — do NOT use them for quests.

### Icons STILL NEEDED (user is collecting — "Uncleared")
1. **Heart states:** half, empty, gold/full, gold/half (only `red heart` = full provided) — to icon-ify the HP bar.
2. **Compass** (Navigator's compass + on-map objective marker).
3. **Wizard/Elder** NPC (save point + "Create Your Hero").
4. **Quartermaster** merchant (drops supply crates; text-only now).
5. **Wolf/beast** (Underdog quest marker).
6. **XP** icon (XP bar) — or confirm `upgrade icon`.
7. Optional menu glyphs: hamburger ☰, display 🖥️, keybinds ⌨, mute 🔇, pause ⏸, restart 🔄, flee 🏃, exit 🚪, lock/unlock 🔒🔓, delete 🗑, water/fishing-spot 💧.

To re-audit every emoji in code+scenes: run a Python scan over `*.gd`+`*.tscn` for chars in emoji ranges, group by char, **write to a UTF-8 `.md` file and Read it** (the Windows console mangles emoji on print). **Delete the temp file after** (last time it was accidentally left in repo root).

## 6. Known TEST HOOK to revert later
- **`FishingSpot.gd`**: every catch currently gives the **Mirror Clone at 100%** (clearly-marked `TEMP TEST HOOK` block) so the clone is easy to test. The original ~6% rare-random-item roll is commented right below it. **Revert when clone testing is done.**

## 7. Suggested next steps
1. New named icons dropped in `Asset/Selected Icon/` → re-check folder, add to `IconDB.MAP`, confirm they load (`ResourceLoader.exists` + `load`), then wire.
2. On **"wire the rest"** → swap HUD hearts / coin / toasts / menu buttons to icons in one consistent pass (§5).
3. **Sound** (later): assets in `Asset/Main Sound/fx` + `/music` (incl. new `click.mp3`, `game coin.mp3`, `upgrade.mp3`, `OvenDing.mp3`, music tracks). Nothing wired to audio yet; user will say which sound fires on which event (item use, level-up, coin, hit, menu click…).
4. Revert the fishing test hook (§6) before shipping.

## 8. Workflow reminders
- After ANY edit → run the two verification commands (§3).
- Full asset import (2600+ PNGs) takes >2 min — run `--headless --import` in the background if a fresh import is needed; the 603 Selected Icon files are already imported.
- Keep temp/scratch files out of the repo root (use the scratchpad dir).
