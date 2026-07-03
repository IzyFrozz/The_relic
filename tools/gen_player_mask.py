"""Regenerate player_groups_mask.png for the player recolor shader.

Run from the repo root any time player.png is repainted:
    python tools/gen_player_mask.py

The repainted player.png gives every customizable part a unique flat palette,
EXCEPT hair and shoes which share the same browns (they are far apart on the
body, so we split them per-frame with connected components instead).

Each opaque pixel of player.png gets a group id encoded in the RED channel of
player_groups_mask.png (alpha 255 where assigned, 0 elsewhere):

    id  group   source colors (sRGB hex)
    --  -----   -----------------------
    40  HAIR    #573a23 #402717  (largest brown blob per 48x48 frame,
                                  plus tiny strays that end above y=33)
    80  SHIRT   #8f0303 #570202
   120  PANTS   #2c65b5 #1d438a #0d205e
   160  SHOES   #573a23 #402717  (remaining brown blobs - feet region)
   200  SKIN    #ac7b5d #c1ac8f #9a5c42

Left unassigned (id 0, untouched by the shader): black outline, eyes #21110d,
weapon metal #787e97 #a4a8b5 #dbd2c7, white slash FX.
"""
from PIL import Image
from collections import deque
import os

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "Asset", "sprites", "characters", "player.png")
DST = os.path.join(HERE, "..", "Asset", "sprites", "characters", "player_groups_mask.png")

BROWNS = {(87, 58, 35), (64, 39, 23)}
SHIRT  = {(143, 3, 3), (87, 2, 2)}
PANTS  = {(44, 101, 181), (29, 67, 138), (13, 32, 94)}
SKIN   = {(172, 123, 93), (193, 172, 143), (154, 92, 66)}

HAIR_ID, SHIRT_ID, PANTS_ID, SHOE_ID, SKIN_ID = 40, 80, 120, 160, 200
CELL = 48
# Small stray brown blobs whose lowest pixel is above this line are hair
# wisps near the head/arms, not feet.
HAIR_STRAY_MAX_Y = 33

img = Image.open(SRC).convert("RGBA")
W, H = img.size
px = img.load()

mask = Image.new("RGBA", (W, H), (0, 0, 0, 0))
mp = mask.load()

# 1. Groups with unique colors: direct per-pixel assignment.
for y in range(H):
    for x in range(W):
        r, g, b, a = px[x, y]
        if a < 200:
            continue
        c = (r, g, b)
        if c in SHIRT:
            mp[x, y] = (SHIRT_ID, 0, 0, 255)
        elif c in PANTS:
            mp[x, y] = (PANTS_ID, 0, 0, 255)
        elif c in SKIN:
            mp[x, y] = (SKIN_ID, 0, 0, 255)

# 2. Browns: hair vs shoes via 8-connected components per frame.
for fy in range(H // CELL):
    for fx in range(W // CELL):
        seen, comps = set(), []
        for ly in range(CELL):
            for lx in range(CELL):
                r, g, b, a = px[fx * CELL + lx, fy * CELL + ly]
                if a < 200 or (r, g, b) not in BROWNS or (lx, ly) in seen:
                    continue
                comp, q = [], deque([(lx, ly)])
                seen.add((lx, ly))
                while q:
                    cx, cy = q.popleft()
                    comp.append((cx, cy))
                    for dx in (-1, 0, 1):
                        for dy in (-1, 0, 1):
                            nx, ny = cx + dx, cy + dy
                            if 0 <= nx < CELL and 0 <= ny < CELL and (nx, ny) not in seen:
                                rr, gg, bb, aa = px[fx * CELL + nx, fy * CELL + ny]
                                if aa >= 200 and (rr, gg, bb) in BROWNS:
                                    seen.add((nx, ny))
                                    q.append((nx, ny))
                comps.append(comp)
        if not comps:
            continue
        comps.sort(key=len, reverse=True)
        for i, comp in enumerate(comps):
            max_y = max(p[1] for p in comp)
            is_hair = i == 0 or max_y <= HAIR_STRAY_MAX_Y
            gid = HAIR_ID if is_hair else SHOE_ID
            for lx, ly in comp:
                mp[fx * CELL + lx, fy * CELL + ly] = (gid, 0, 0, 255)

mask.save(DST)
print("wrote", os.path.normpath(DST))
