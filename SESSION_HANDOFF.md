# SESSION HANDOFF — The Relic (Godot 4.6 JRPG)

Drop this into the first message of the next session.

---

## 0. Snapshot
- **Branch:** `testingHeng` · large uncommitted working tree (last commit `db832124 v0.8.1`).
- **Engine:** Godot **4.6.1.stable**, binary at `C:/Program Files/Godot/Godot.exe` (NOT on PATH — use the full path).
- **Do NOT commit or push unless explicitly asked.** Commit directly on `testingHeng`. End commit messages with the Co-Authored-By line.
- `git status` currently shows ~15.6k changed paths — almost all of that is the asset
  quarantine move (§8), not code.

## 1. What this project is
Top-down pixel JRPG. Overworld exploration + turn-based combat. Win: collect 10 coins → Street Kid gives a key → open chest → get the **Ancient Relic** → turn it in (keep-vs-turn-in choice) → post-game continues.
- Tile grid **16×16**. Player sprite 48×48, NPCs 32/64. Window 1920×1080, `canvas_items` stretch, camera zoom ~6×.

## 2. Architecture
`main.tscn` (root `main`) instances `map.tscn`, `character.tscn` (all mobs under `Character`), `foreground.tscn`, `ui.tscn`, + `OverworldHUD.gd`. Player is `mainplayer` (direct child of `main`).

**Autoloads** (`project.godot [autoload]`), in order:
`QuestManager`, `KeybindManager`, `Toast`, `DialogueManager`, `PromptHUD`, `ScreenFade`, `WorldMap`, `IconDB`, **`SFX`** (`res://sfx.tscn`).

**HARD RULES / gotchas:**
- **NEVER edit `map.tscn` or `foreground.tscn`.** New world objects go in `main.tscn`.
- **Autoload order matters.** `DialogueManager._ready` must NOT touch `SFX` (SFX loads later) — that's why it sets `_root.visible = false` directly instead of calling `_hide_box()`.
- **Player-recolor shader trap:** recolor is mask-driven; `mainplayer._process` disables `recolor_on` whenever `sprite.modulate != WHITE`, and force-resets modulate to WHITE outside combat.
- **Container vs anchors:** a Control inside a `VBox/HBoxContainer` has its rect driven by the parent — `set_anchors_preset` is ignored. Use **size flags**.
- **RichTextLabel ≠ Label:** theme keys are `normal_font_size` / `default_color`; no `horizontal_alignment` (use `[center]`).
- **`PanelContainer` is NOT a subclass of `Panel`** — a helper typed `(p: Panel)` will reject it at RUNTIME only. Type such helpers as `Control`.
- **Off-island coords:** house interiors (`x ≈ -3000…-4900`), combat arena (`x ≈ -2971 / -1632`). `WorldMap.OVERWORLD_BOUNDS` excludes them.

## 3. Verification workflow (ALWAYS run all three after edits)
```bash
GODOT="/c/Program Files/Godot/Godot.exe"
"$GODOT" --headless --editor --quit-after 400 2>&1 | grep -iE "SCRIPT ERROR|Parse Error|Compile Error|Failed to load"
"$GODOT" --headless --quit-after 60 2>&1 | grep -iE "SCRIPT ERROR|Invalid"
"$GODOT" --headless main.tscn --quit-after 60 2>&1 | grep -iE "SCRIPT ERROR|Invalid"
```
- **Parse-clean ≠ correct.** Runtime type errors (bad `var x := y` inference, wrong
  parameter class) only surface on a scene RUN. Several bugs this session were caught
  only by a throwaway probe script.
- **Probe scripts are the main tool here.** Write `_probe.gd` (`extends SceneTree`,
  `func _initialize()`), run with `--headless --quit-after N --script res://_probe.gd`,
  print lines prefixed `PROBE`, then **delete it**. Notes:
  - autoloads are NOT available as bare identifiers — use `root.get_node("SFX")`.
  - `--quit-after` counts FRAMES; a 2.4s effect needs ~900.
  - typed `var x := <untyped>` fails to parse; use `var x: bool = …`.
- **Bash heredocs mangle backslashes.** A `\` line-continuation written via
  `python - <<'PY'` came out as a literal `\n` and broke the parser twice. Use the
  Edit tool for lines containing `\`, or build them with `chr(92)`.
- Combat/fishing need live input → validate by probe + ask the user to test.
- **Edit tab gotcha:** GDScript match-case labels are 2 tabs, bodies 3. Re-Read and count.

## 4. Difficulty modes (NEW — big one)
`QuestManager.difficulty` = `Difficulty.NORMAL` | `Difficulty.RELIC`, saved with the run.
Set at character creation AND in Settings (main menu hub + a cycling button in PauseMenu).
Helpers: `is_relic_difficulty()`, `difficulty_name()`.

**RELIC ("Chosen by the Relic") adds:**
- XP required ×1.25 across the whole curve (`DIFF_XP_REQUIRED_MULT`).
- Fishing XP ×0.88 (`DIFF_FISHING_XP_MULT`, folded into `FishingSpot._build_xp_bands`,
  which rebuilds when the mode changes mid-run).
- **Enemy threat traits** (§5). Normal rolls none at all.

Applied in BOTH modes (tier-appropriateness, not difficulty): enemy item tiers 16–20,
and `ITEM_UPGRADES` (a mob stops bringing Potion once it knows Bandage, etc.).

## 5. Enemy threat traits (`MobEnemy.ENEMY_THREATS`)
15 traits, each with `min_level` and a `proc` chance on a **falling curve** (50% at
level 3 → 18% at 17) so the nastiest ones are occasional spikes. **Nothing fires
automatically** — use `threat_procs(id)` in combat, `has_threat(id)` only for display.

Slots: `1 + floor((level-5)/5)`, min 1, capped by how many are unlocked — level 10 → 2,
15 → 3, 20 → 4.

Two are **threshold-driven, `proc: 0.0`** (never roll):
- **👥 Splitter** (lv12) — a double every **80 damage taken** (`SPLIT_DAMAGE`).
  `_note_enemy_damage()` is hooked into all 6 enemy-HP-reduction sites.
- **🏺 Relicbound** (lv16) — beam each time HP falls past a **100 mark**
  (`BEAM_HP_MARK`), tracked by band via `_last_beam_mark`; healing back re-arms it.

Threat display: its own red panel LEFT of the enemy nameplate (`CombatUI.threat_panel`),
not mixed into the buff line. Verified clear of the item arcs at 1920 and 1280.

**All damage numbers must be multiples of 10** — there is no half-heart art.

## 6. Relic beam FX
`MobEnemy._fx_beam(target, colour, width_mult)` — shared by both relics. Light gathers
in the sky ABOVE the target and a column slams down; target shakes and strobes white.
- Player relic: `("enemy", BEAM_TEAL, 1.0)`, ~2.4s.
- Enemy Relicbound: `("player", BEAM_RED, 0.55)` — same FX, slimmer, red/orange.
- Restores the target sprite's position AND modulate on every exit path (`_fx_beam_restore`)
  — `_fx_damage` runs right after and would otherwise capture the strobed white.
- Loops `SFX.relic_beam_fire`; `stop_loop("relic_beam")` is also in
  `_reset_all_combat_modifiers` so a fight ending mid-beam can't leave it droning.

## 7. Tuning reference (all verified by probe)
- **XP curve** (`QuestManager.xp_required_for`, derived from level, NOT read back from
  the save): ×1.35 lv1-7, ×1.18 lv8, **×2.45 one-off step at lv9**, ×1.13 from lv10.
  Gives ~5.6 fights/level at 9-10 rising to ~7 by 16 (the item-unlock band).
- **Fishing**: `XP_SCALE = 0.5625`. Per-tier XP **bands** (±7% jitter) are built so they
  can NEVER overlap — a bigger fish always pays more.
- **Fish spawn**: weights strictly descend tiny→legendary but shallowly (~×0.97/rung).
  Legendary 1 in 18.8, exotic-or-better 1 in 6.1.
- **Fish sprites**: `IconDB.FISH_VARIANTS` — pools built from sprites **ranked by measured
  opaque bbox area**, ±2 window per tier. Tank art (`fishes (43)`) is exclusive so it
  can never hint at the tier; the reveal is the toast.
- **Fishing difficulty**: legendary speed is the CEILING — level scaling clamps there.
- **Relic**: 200 base charge, +40 per use **within the same fight** (resets each fight).
  Double cleanse: strips every enemy buff AND every player debuff.

## 8. Asset cleanup (done this session)
`Asset/_unused/` holds **7804 files** with no reference anywhere (no `res://`, no `uid://`,
no filename string). It has a **`.gdignore`**, so Godot skips the whole tree — no import,
not in the FileSystem dock, no bloat — but nothing is deleted and it's all still in git.
`Asset/_unused/README.txt` explains how to restore one.

Live asset counts now: Selected Icon 108 · Pixel Crawler 86 · Main Sound 57 · UI Elements 70 · rest ≤7.

**Deliberately NOT moved:** `Asset/Main Sound` (SFX slots are filled by dragging files in
the Inspector, so unused-today ≠ unwanted) and `Asset/UI Elements`.

If you add art, drop it in the live folders — re-running the scan would otherwise
quarantine anything you haven't wired up yet.

Also removed: 11 stray `*.tmp` files in the repo root (~3 MB of Godot atomic-save
leftovers that had been committed back in July). `*.tmp` is now in `.gitignore`.
They're still in git history if one is ever needed.

## 9. Emoji policy (the user cares about this)
**A plain `Label`/`Button` ALWAYS renders a raw emoji with the OS colour-emoji font** —
which is the mismatched glyph the project is trying to be rid of. Only `RichTextLabel`
can show `IconDB.iconify()`'s `[img]` tags.

Rules:
- `RichTextLabel` → `IconDB.iconify(text, size)`.
- `Button` → `IconDB.decorate_button(btn, glyph, label)`.
- No icon art for that concept → **remove the emoji, leave plain text.**

All 29 offending `.text` sites were stripped this session. Typographic marks
(`✓ ✕ ▸ ▪ · ☰ ↩ ▶`) are fine and were left alone. Still emoji-less by design:
display, keyboard, mute, pause, restart, delete, lock, timer, warning, hamburger.

## 10. ⚠️ Open items / next steps
1. **Play-test the RELIC difficulty.** A level 16+ foe can roll 4 traits including both
   Splitter and Relicbound — likely needs tuning. `THREAT_SLOT_EVERY` is the one knob.
2. **Audio normalization** — STARTED, NOT FINISHED. `ffmpeg` is available. Every file was
   measured but the values were never written into code. Plan: a `FILE_TUNING` table in
   `SFX.gd` keyed by filename, applied as `p.play(offset)` + a per-file dB trim.
   Worst leading silence: `universfield-punch-03` 0.28s, `relic get` 0.30s.
   **Precedent:** `dialogue_blip` is an 8.8s track of 81 blips and peaks at −18.3 dB —
   it needed `BLIP_GAIN_DB = +8` and to be LOOPED, not retriggered. Other slots may be
   similarly mis-levelled.
3. **Empty SFX slots to fill by hand:** `ui_scroll`, `relic_beam_charge`, `relic_beam_fire`
   (the beam one is looped — give it something sustainable, ~1.5s+). All fall back to
   something so nothing is silent.
4. **Placeholder art** — see `PLACEHOLDER_ASSETS.md`.
5. **Dead code sweep** — `PromptHUD` autoload now has ZERO call sites (every interactable
   uses `IconDB.add_marker` instead). `SaveNPC.gd` and `QuestNPC.gd` are referenced by no
   scene. All three are removal candidates.
6. **Main-menu screens scroll now** rather than showing everything at once at 1080p. If
   that's unwanted, trim content height (the 150px art banner + 168px preview box).

## 11. Workflow reminders
- After ANY edit → run all three verification commands (§3).
- **Audit before claiming done.** Grep for real call sites; don't assume a slot/feature is
  wired because it exists.
- **Measure, don't guess.** Several "bugs" this session were fine in code and were really
  file-level facts (sample loudness, sprite sizes). ffmpeg/PIL are available — use them.
- When a request's numbers conflict with an earlier explicit goal (e.g. "more big fish"
  vs "nerf fishing XP"), say so and show the trade-off rather than silently picking one.
- Keep temp/scratch files out of the repo root (use the scratchpad dir); delete probe
  scripts when done.
