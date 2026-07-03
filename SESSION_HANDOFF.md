# Session Handoff — The_relic (JRPG)

> Paste this whole file into the next chat's first message. It captures everything from the previous session so a cold start can continue seamlessly.

---

## 0. READ FIRST — critical context

- **Correct working directory: `E:\Code\Godot\DAD\The_relic`** (top-level, sibling of the `jrpg` folder). **Do ALL edits, `run_project`, and git here.**
- The previous session accidentally worked in a **stale duplicate** at `E:\Code\Godot\DAD\jrpg\The_relic`. All of that work has already been **ported into the real repo** (file-copied, hash-verified, compile-checked). The jrpg copy has since been **emptied**; only an empty locked husk remains. **After closing that session, delete the whole `E:\Code\Godot\DAD\jrpg` folder** (it only holds the empty husk + two stray git dotfiles).
- **Branch: `testingHeng`** (base commit `c4751ca` = v0.6.6). Both repos are clones of `IzyFrozz/The_relic`.
- **Do NOT touch `map.tscn` / `foreground.tscn`** — teammate Sal owns those on `testingSal`.
- Godot **4.6.1.stable**. Windows. Godot MCP is available (`run_project` to compile-check).
- Nothing has been committed or pushed — all changes are uncommitted working-tree edits in the real repo.

---

## 1. The 10 tasks (from Heng) and their status

| # | Task | Status |
|---|------|--------|
| 1 | Hook idle animations (IdleSide/IdleUp/default=IdleDown) by last facing dir | ✅ done |
| 2 | Re-key recolor shader for repainted sprite → 5 groups | ✅ done |
| 3 | Player level cap 20+ with +20 HP/level | ✅ done |
| 4 | Modular level-gate system for mechanics | ✅ done |
| 5 | Side-quest framework (cyclable log, activation, rewards) | 🟡 code-complete, **not yet visually tested in-game** |
| 6 | Fishing minigame (Stardew-style) + fisherman NPC + fish rewards | ⬜ not started (design notes below) |
| 7 | Tutorial/intro flow after char creation + non-respawning tutorial mob | ⬜ not started |
| 8 | Keybind editing in main menu (before starting game) | ⬜ not started |
| 9 | Rework supply-drop presentation/lore (keep fixed-round mechanics) | ⬜ not started |
| 10 | Integrate UI Elements pack (banners, bars, cursor, icons) | ⬜ not started |

Everything below marked ✅/🟡 is present in the real repo and **compiles cleanly** (only a harmless pre-existing integer-division warning at `QuestManager.gd`).

---

## 2. What was built (files changed this session)

**Modified:** `mainplayer.gd`, `QuestManager.gd`, `main_menu.gd`, `MobEnemy.gd`, `OverworldHUD.gd`, `HealingItem.gd`, `QuestGiverNPC.gd`, `ElderNPC.gd`
**New:** `PlayerSkin.gd`, `player_recolor.gdshader`, `LevelGate.gd`, `SideQuestDB.gd`, `Asset/sprites/characters/player_groups_mask.png`, `tools/gen_player_mask.py`
**Also preserved into real repo:** `Asset/UI Elements/` (144 files — reorganized UI pack for task #10; the original `Tiny Swords (Free Pack)/UI Elements/` still exists too).

### Task 1 — Idle animations
- `mainplayer.gd` `_set_idle_facing(dir)` now plays `IdleSide` / `IdleUp` / `default` (down) based on last facing dir, via new helper `_play_if_changed()`. Has a **graceful fallback** to freezing on Walk-frame-2 if the Idle anims are ever missing.
- Real repo's `main.tscn` AnimatedSprite has `IdleSide`, `IdleUp`, and `default`(=idle-down) — confirmed present, so it works.

### Task 2 — Recolor (now MASK-DRIVEN, 5 groups)
- Heng repainted `player.png` so every part is a distinct flat color. Recolor changed from 3 color-matched groups (Outfit/Sash/Skin) to **5 mask-driven groups: Hair, Shirt, Pants, Shoes, Skin.**
- Hair & shoes share the same browns, so they're separated by a **region mask** `player_groups_mask.png` (RED channel = group id: 40 hair / 80 shirt / 120 pants / 160 shoes / 200 skin / 0 untouched).
- **Regenerate the mask** whenever `player.png` is repainted: `python tools/gen_player_mask.py` (then Godot re-imports it).
- `player_recolor.gdshader` samples the mask, remaps each group to chosen color × luminance (preserves shading). FX-safe via `recolor_on` uniform (mainplayer sets it 0 when `sprite.modulate != white`).
- `PlayerSkin.gd` — `make_material(hair,shirt,pants,shoes,skin)` / `apply_colors(...)`, preloads mask, holds `DEF_*` base shades. Shared by menu preview + player.
- `QuestManager` vars: `hair_color/shirt_color/pants_color/shoes_color/skin_color` (saved as html hex; legacy outfit/sash saves are mapped on load).
- `main_menu.gd` customize view: **5 ColorPickerButtons** in 2 rows + live preview. Card height bumped to 1010.
- ⚠️ **Not yet visually verified** that each mask group maps to the intended body part on Heng's exact repaint — worth eyeballing in-game / in the char-creator.

### Task 3 — Level cap
- `QuestManager.gain_xp()` is uncapped; +20 MAX_HEALTH per level forever. XP curve made two-stage (×1.35 <lvl8, ×1.18 after) so lvl 20+ is reachable. Items still only defined through lvl 15 (intentional).

### Task 4 — Level-gate system
- `LevelGate.gd` (preload const): `GATES` dict (id → level/label/unlock_toast). `is_unlocked(id)`, `required_level(id)`, `hint(id)`, `announce_unlocks_at(level)`.
- First gate: `"fishing"` at level 5. `QuestManager.gain_xp` calls `LevelGate.announce_unlocks_at(new_level)` on level-up to toast when a mechanic opens.
- Reusable for future level-locked NPCs/mechanics — just add to `GATES`.

### Task 5 — Side-quest framework (code-complete, needs playtest)
- `SideQuestDB.gd` (preload const): `QUESTS` dict of 7 side quests + `INITIALLY_AVAILABLE`. Types: `kill_count`, `loadout_kill`, `underdog_kill`, `coin_lifetime`, `potion_count`, `talk_npcs`, `fish_count`. Each has title/emoji/desc/how/goal/params/reward/unlocks.
- Lifecycle: **locked → available → active → done.** Unlock chains via `unlocks`.
- `QuestManager` side-quest state (all saved/loaded): `side_quest_states`, `side_quest_progress`, `coins_lifetime`, `potions_lifetime`, `fish_caught`, `talked_npcs`; signal `side_quests_changed`.
  - `init_side_quests()` (called from `reset_to_defaults` at char creation + on load), `accept_side_quest(id)`, `notify_quest_event(event, ctx)`, `record_npc_talk(id)`, `record_fish_caught()`, `_complete_side_quest()` (grants XP/item, reveals unlocks, toasts).
- **Event hooks wired:** enemy defeated → `MobEnemy.gd` (fires BEFORE gain_xp so `underdog` sees pre-levelup level, passes `enemy_level`); coin → `QuestManager.collect_coin`; potion → `HealingItem.gd`; npc talk → `QuestGiverNPC.gd` (`street_kid`) + `ElderNPC.gd` (`wizard`); fish → `record_fish_caught()` (awaiting fishing minigame).
- **Cyclable quest log** in `OverworldHUD.gd`: ◀ ▶ nav across 4 pages — **Main Quest / Active / Rumors / Completed** (badge counts). Rumors page builds an **Accept button per available quest**; accepting jumps to Active. Signal-driven refresh (NOT per-frame — it builds buttons). Scrollable body.
- **2 new quest-reward combat items** (NOT level-gated; unlocked by completing quests), fully wired in `MobEnemy.gd` (player use + reset):
  - `phoenix_feather` 🪶 — full heal + regen ×3 (reward for `underdog`).
  - `war_banner` 🚩 — next attack ×2 damage (reward for `mob_slayer`). Uses `player_rally` flag.
- **TODO for #5:** playtest the log UI, confirm accept/progress/completion/reward flow and the 2 new items in combat; tune quest goals/rewards to taste.

---

## 3. Pending tasks — notes / starting points

### 6. Fishing minigame (BLOCKED on nothing now; level-gate + quest hook already exist)
- Stardew-style: vertical bar + player-controlled box (Space raises, gravity/bounce), fish icon bobs randomly (speed by fish size), keep box on fish to fill 100% → reel. Emoji visuals (no art yet).
- Gate behind level 5 via `LevelGate.is_unlocked("fishing")`; fisherman NPC brushes the player off below lvl 5 (reuse `LevelGate.hint("fishing")`).
- Rewards: define fish uses (healing consumable? sell/trade? quest turn-in for `gone_fishing` quest which already exists and calls `fish_count`). **5% chance to fish a new playable item** (not level-locked once obtained).
- Fishing spots near water: **do NOT edit map.tscn/foreground.tscn** — add via a separate scene/spawner or place in `main.tscn`.
- Call `QuestManager.record_fish_caught()` on each successful catch (already hooked to the `gone_fishing` side quest).

### 7. Tutorial / intro flow
- Replace bare drop-at-spawn with: keybind overview + teach the 2 loops (explore/quests, combat). Spawn ONE lvl-1 mob at start/safe island for a guided combat walkthrough. **That tutorial mob must NOT respawn** after the 5-min timer (only this one is non-respawnable — see `QuestManager.defeated_enemies` / `RESPAWN_COOLDOWN_SECONDS` in `MobEnemy`).

### 8. Keybind editing in main menu
- Reuse the in-game keybind UI/logic (`KeybindManager.gd`) and expose it from `main_menu.gd` before starting a game.

### 9. Supply-drop lore rework
- KEEP the fixed-round drop mechanic (both parties get same items at fixed rounds — Heng likes the consistency). Only fix the STORY: explain why/where/how items appear mid-combat; give a proper narrative intro instead of unexplained round-2 drops. Logic is in `MobEnemy.gd` (tier pools `TIER_POOLS_LV6_PLUS`, drop scheduling).

### 10. UI Elements pack integration
- Assets now in real repo at **`Asset/UI Elements/`** (preserved) and original `Asset/Tiny Swords (Free Pack)/UI Elements/`.
- Banner = 9-slice/tileset (corners/edges/center) → use `NinePatchRect` / `StyleBoxTexture`. Bars for stamina/XP/HP. Update mouse cursor visual. Icons are generically named (`Icon_06`…`Icon_12`) — **review each PNG visually** to identify (arrow, X, music, settings…). Apply across HUD + new fishing/quest/tutorial UI.

---

## 4. Architecture quick-reference (for the next session)

- **Autoloads/singletons:** `QuestManager` (all persistent state, save/load, side quests, items `ITEM_META`, `item_unlocks`), `DialogueManager`, `PromptHUD`, `Toast`, `KeybindManager`.
- **Preload-const modules** (not autoloads): `PlayerSkin`, `LevelGate`, `SideQuestDB` — reference via `const X = preload("res://X.gd")`.
- **NPCs:** Street Kid = `QuestGiverNPC.gd` (node named `QuestNPC` in main.tscn; the quest giver + relic turn-in = WIN). Wizard checkpoints = `ElderNPC.gd` (save/respawn anchor; there are `ElderNPC` + `ElderNPC2`). `QuestNPC.gd` is UNUSED.
- **Combat** lives in `MobEnemy.gd` (big state machine; player/enemy status-flag pairs, item-use match blocks, XP on kill). `CombatUI.gd` for combat HUD.
- **Main quest:** collect 10 coins → trade Street Kid for key → open chest → return relic → win.
- **Memory system:** persistent notes at `C:\Users\User\.claude\projects\E--Code-Godot-DAD-jrpg-The-relic\memory\` (MEMORY.md index). Already updated this session with `real-repo-location`, refreshed `player-recolor`.
- **Verify changes:** use Godot MCP `run_project` on `E:\Code\Godot\DAD\The_relic`, then `get_debug_output` (expect only the integer-division warning).

---

## 5. Immediate next steps (suggested order)
1. Confirm you're in `E:\Code\Godot\DAD\The_relic`; delete leftover `E:\Code\Godot\DAD\jrpg`.
2. Playtest tasks 1–5 in-game (idle anims, 5-color char creator, level-ups past 15/20, quest log cycling + accepting a rumor + completing `first_blood`, the 2 new items).
3. Then pick up tasks 6–10 (fishing is the biggest; its level-gate + side-quest hook are already in place).
