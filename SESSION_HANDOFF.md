# Session Handoff — The_relic (JRPG)

> Paste this whole file into the next chat's first message. It captures the project state so a cold start can continue seamlessly.

---

## 0. READ FIRST — critical context

- **Working directory: `E:\Code\Godot\DAD\The_relic`** (do ALL edits, `run_project`, git here).
- **Branch: `testingHeng`.** It was merged up to `testing` this session, so it now sits at commit **`82cca81` (v0.8.0)** which contains all of tasks 1–6. Everything in the "uncommitted" list is on top of v0.8.0 and **NOT yet committed**.
- **Godot 4.6.1.stable, Windows.** Godot MCP available: `run_project` (compile-check) → `get_debug_output`. Expect only ONE harmless warning: `Integer division … at QuestManager.gd:314`. Any OTHER error = something you broke. Whole project compiles clean as of end of session.
- **DO NOT EVER edit `map.tscn` or `foreground.tscn`.** Teammate (Sal) owns them; editing risks git conflicts. **Read-only is fine** — to find coordinates/water/bounds, load them in a throwaway probe scene and inspect (see §5). Confirmed untouched in git this session.
- **`character.tscn` IS ours to edit** — it holds the overworld mob layer (mob1..mob20, each an MobEnemy with `enemy_level`) and is instanced into `main.tscn`. `main.tscn` is also ours.
- **Nothing is committed yet.** Uncommitted working-tree changes (all compile clean):
  - Modified: `CombatUI.gd`, `FishermanNPC.gd`, `MobEnemy.gd`, `QuestManager.gd`, `character.tscn`, `main.gd`, `main_menu.gd`, `project.godot`
  - New: `ScreenFade.gd` (+ `.uid`)

---

## 1. The 10-task list (from Heng) — status

| # | Task | Status |
|---|------|--------|
| 1 | Idle animations by facing dir | ✅ done (in v0.8.0) |
| 2 | Recolor → 5 mask groups (exact hex + shading + white) | ✅ done (in v0.8.0) |
| 3 | Player level cap 20+ | ✅ done |
| 4 | Modular level-gate system | ✅ done |
| 5 | Side-quest framework (rumour→available→active, max-3, Q/E nav) | ✅ done |
| 6 | Fishing minigame + fisherman + rewards | ✅ done |
| 7 | Tutorial/intro flow + non-respawning tutorial mob | ✅ **done this session** |
| 8 | Keybind editing in main menu | ✅ **done this session** |
| 9 | Supply-drop lore rework | ✅ **done this session** |
| 10 | UI Elements pack integration | 🟡 **partial — cursor done, icons reviewed; BARS + BANNERS remain** |

Plus ad-hoc requests handled this session: combat fade transition, level-label placement fix.

---

## 2. What was built THIS session (all on top of v0.8.0, uncommitted)

### Combat fade transition — NEW `ScreenFade.gd` autoload ✅ compile-verified
- `ScreenFade.gd` = autoload CanvasLayer (layer 200) with a full-screen black `ColorRect`; `await ScreenFade.fade_out()` / `fade_in()` (default 0.22s). Registered in `project.godot` `[autoload]` as `ScreenFade="*res://ScreenFade.gd"`.
- `MobEnemy.start_combat()` is now `async`: fades OUT before the camera-cut/teleport, fades IN after the combat UI opens. Only caller is `_on_deadzone_body_entered` (fire-and-forget, safe).
- `MobEnemy._check_combat_end_conditions()` win + lose paths: fade out → reposition/switch camera → hide enemy → fade in. Win path restructured to `if is_tutorial_mob … else …` with a single `fade_in()` + `return true`.

### Level label placement fix ✅ visually verified (probe)
- In `MobEnemy._setup_level_display()` the "Lv. N" label was floating ~45px above heads (used deadzone radius). Now anchored to the sprite's real top edge (`AnimatedSprite2D` frame height × scale) and horizontally centered. Result pos ≈ `(-16, sprite_top-12)`.
- TWO Area2Ds per mob: small scene-authored **`deadzone`** (combat trigger, unchanged) + code-built **`SightZone`** (2.6× radius, only toggles label visibility). Label color-codes threat vs `player_level` (green→yellow→red).

### Task 7 — Tutorial / intro flow ✅ verified (probe-tested)
- `main.gd._maybe_show_intro_tutorial()` — once per fresh character on overworld entry: dialogue covering WASD/Shift, E-interact, the explore→quest→reward loop, quest log + Q/E, combat heads-up. Gated by `QuestManager.intro_tutorial_done` (saved).
- Tutorial mob = **`mob1`** in `character.tscn` (`is_tutorial_mob = true`, Lv1, near spawn). First pull shows a combat walkthrough dialogue (turn-based, Attack/Items, HP bars, Quartermaster/supply). On defeat sets `tutorial_mob_defeated=true`, `_permanently_dead=true`, and **skips the respawn dict** → never respawns (survives save/load; `MobEnemy._ready` restores the hidden state on load). Gated by `combat_tutorial_done`.
- QuestManager saved+reset flags added: `intro_tutorial_done`, `combat_tutorial_done`, `tutorial_mob_defeated`.
- **Safe island cleared**: only `mob1` remains on the spawn island; the other 7 (mob1_2/1_3/1_4/2/3/4/5) relocated to the mainland in `character.tscn`. (mob6–mob20 were already on the mainland.)

### Task 8 — Keybinds in main menu ✅ visually verified (probe)
- `main_menu.gd`: added a **Controls** section in the Settings view — one rebind button per `KeybindManager.action_ids()` + "Reset Keys to Defaults". Added `_input()` (captures next key, Esc cancels), `_begin_rebind()`, `_refresh_keybind_labels()`, vars `keybind_rows`/`_rebinding_action`. Shares `KeybindManager` so binds persist into the game. `_show_view()` bumps settings card height to 940 + cancels pending rebind on view change.

### Task 9 — Supply-drop lore ✅ compile-verified
- **Mechanic unchanged** (fixed-round, both fighters get identical items — Heng likes it). Only the *story* changed: a roaming **Quartermaster** shadows every brawl and lobs an identical crate to both sides at set rounds ("war's good for business; a fair fight lasts longer").
- Text updated in: `MobEnemy` combat-tutorial lines, opening-crate line in `start_combat`, mid-combat drop line in `_conclude_round_cycle_ticks`, and `CombatUI` `drop_countdown_label`.

### Task 10 — UI Elements pack 🟡 PARTIAL
- **Assets**: `Asset/UI Elements/` (reorganized copy) and `Asset/Tiny Swords (Free Pack)/UI Elements/UI Elements/` (original). Contains: `Bars/` (BigBar_Base+Fill, SmallBar_Base+Fill — wooden frame + red fill, horizontal), `Banners/` (Banner.png 9-slice-able + Banner_Slots), `Buttons/`, `Cursors/` (Cursor_01 arrow, 03 "disabled", …), `Icons/` (Icon_01..12), `Papers/`, `Ribbons/`, `Human Avatars/`, `Wood Table/`, `Swords/`.
- **DONE — Cursor**: `main_menu.gd` `Input.set_custom_mouse_cursor(Cursor_01, CURSOR_ARROW, Vector2(3,2))` at boot (global, persists across scenes).
- **DONE — Icon review**: the `Icons/` are **item-style glyphs** (Icon_01=hammer, 06=shield, 08=orange arrow, 11=ring, …), NOT UI-control icons (no music/settings/X). No clean 1:1 to control glyphs. Candidate reuse: Icon_08 (arrow) for quest-log ◀▶. Do a full 12-icon pass when integrating.
- **TODO — Bars**: re-skin HP / stamina / XP bars with `BigBar_Base` (frame → `NinePatchRect` or `TextureProgressBar.texture_under`) + `BigBar_Fill` (`texture_progress`). Current bars are `StyleBoxFlat` panels — stamina bar in `mainplayer.gd` (`_build_stamina_bar`/`_update_stamina_bar`, world-space above player), XP bar in `OverworldHUD.gd`. Needs pixel-accurate sizing + **visual iteration via probe** (was deferred; do NOT do blind).
- **TODO — Banners**: 9-slice `Banner.png` (`StyleBoxTexture` w/ expand margins) for panel headers/titles. Also needs visual iteration.
- **Optional — Buttons**: `Buttons/` wooden textures could re-skin `Button` styleboxes (higher layout risk).

---

## 3. ON HOLD — recall when Heng asks

**Buff-item once-per-turn rule** (paused mid-implementation). Goal: each non-healing combat item usable only ONCE per player turn; different buffs still STACK; healing exempt.
- Already in `MobEnemy.gd`: `var items_used_this_turn: Dictionary = {}` and `const HEAL_ITEMS := ["potion","bandage","phoenix_feather"]` (declared, NOT yet used).
- Remaining: in `use_player_item()` reject a non-heal item already in `items_used_this_turn` (return BEFORE it's consumed/erased) and mark it used on successful apply (incl. the magnet/chain_hook early-return branches); `items_used_this_turn.clear()` at each player-turn start (before the two `combat_ui.start_player_turn()` calls — in `start_combat` and `_conclude_round_cycle_ticks`).
- Why: supply drops accumulate DUPLICATE equipped items in `player_inventory` across rounds, so a player can currently spam grindstone multiple times/turn (+20 each).

---

## 4. Architecture quick-reference

- **Autoloads**: `QuestManager` (all persistent state, save/load, side quests, `ITEM_META`, `item_unlocks`, tutorial/fishing/combat flags), `KeybindManager`, `Toast`, `DialogueManager` (`say`/`start`, `dialogue_finished` signal, `is_active`), `PromptHUD` (`[E]` chips; `request`/`release`; nodes may implement `get_prompt_target()`), **`ScreenFade`** (NEW).
- **Preload-const modules**: `PlayerSkin`, `LevelGate`, `SideQuestDB` — `const X = preload("res://X.gd")`.
- **Combat**: `MobEnemy.gd` (state machine; `use_player_item`, `_check_combat_end_conditions`, supply drops, camera switch, `async start_combat`). `CombatUI.gd` = combat HUD (attack/item buttons now fire on first click — no confirm popup). Combat mobs in `character.tscn`. `main.gd` = overworld; `main_menu.tscn` = `run/main_scene`.
- **NPCs**: `QuestGiverNPC` (Street Kid, quest giver + relic turn-in = WIN), `ElderNPC` (Wizard save/respawn), `FishermanNPC` (fishing, lvl-5 gate; note: it's a CharacterBody2D with a child `Area2D` for detection, wired in `_ready`). Overworld interact = `Input.is_action_just_pressed("interact")` (E), guarded per-NPC by `QuestManager.ui_arrow_nav_open` and `QuestManager.is_fishing`.
- **Keybinds** (`project.godot`): move WASD/arrows, interact=E, sprint=Shift.
- **Save/load**: `QuestManager.save_game/load_game`, `reset_to_defaults()` at char creation. New persistent var → wire into ALL THREE.
- **Verify**: `run_project` → `get_debug_output`. Clean = only the QuestManager:314 integer-division warning.

---

## 5. Workflow gotchas learned across sessions

- **Throwaway probe scenes** are the reliable headless way to verify UI/placement/coords: write `_x_probe.gd` (`extends Node2D`) + `_x_probe.tscn`, `load(...).instantiate()`, add a `Camera2D` (`make_current()`), `await` a couple frames, `get_viewport().get_texture().get_image().save_png("user://x.png")`, then Read `C:\Users\User\AppData\Roaming\Godot\app_userdata\JRPG\x.png`. **ALWAYS delete probe files after** (`rm _x_probe.*` + the png). None remain now — confirmed.
- Map coords read-only: instance `map.tscn`, walk `TileMapLayer`s, `get_used_cells_by_id(source_id)` where the atlas texture path contains e.g. `Water_tiles`; convert `layer.to_global(layer.map_to_local(cell))`.
- **Recolor shader gotcha** (memory `player-recolor-shader`): on canvas_item, built-in `COLOR` = texture×modulate — OVERWRITE, never multiply. `MODULATE` builtin does NOT exist in 4.6. Preview must be a Sprite2D (sheet-normalized UV), not TextureRect+AtlasTexture.
- Making a func `async` (adding `await`): check callers — fire-and-forget is fine; callers needing the result must `await`.
- **Memory dir**: `C:\Users\User\.claude\projects\E--Code-Godot-DAD-The-relic\memory\` (MEMORY.md index).

---

## 6. Immediate next steps (suggested)

1. `run_project` once to confirm clean (only QuestManager:314 warning).
2. Finish **Task 10**: bars (XP first — screen-space, easiest to verify), then banners, then a full 12-icon pass. Verify each with a probe.
3. When Heng says so, do the **on-hold buff-item once-per-turn** change (§3).
4. Consider committing this session's work on `testingHeng` (nothing committed yet).
