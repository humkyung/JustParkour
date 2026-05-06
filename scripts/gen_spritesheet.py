"""Generate assets/spritesheet.png matching the layout expected by main.lua.

Grid: 4 cols x 4 rows of 64x64 cells (256x256 total).
Row 0: [idle] [run-2] [run-3] [run-4]
Row 1: [jump-1] [jump-2] [jump-3] [jump-4]
Row 2: [duck] [crawl-2] [crawl-3] [crawl-4]
Row 3: [climb-1] [climb-2] [climb-3] [climb-4]

Stickman faces RIGHT by default (direction=1 in main.lua flips via X-scale).
"""
from PIL import Image, ImageDraw
from pathlib import Path

CELL = 64
COLS = 4
ROWS = 4
W, H = COLS * CELL, ROWS * CELL

COLOR = (25, 25, 35, 255)
LW = 2
HR = 5  # head radius


def head(d, cx, cy, r=HR, face_right=True):
    d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=COLOR, width=LW)
    ex = cx + 2 if face_right else cx - 3
    d.ellipse((ex, cy - 1, ex + 1, cy), fill=COLOR)


def line(d, *pts):
    d.line(list(pts), fill=COLOR, width=LW, joint="curve")


def at(col, row):
    return col * CELL, row * CELL


def main():
    out = Path(__file__).resolve().parent.parent / "assets" / "spritesheet.png"
    out.parent.mkdir(parents=True, exist_ok=True)

    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # ===== Row 0 col 0: IDLE =====
    ox, oy = at(0, 0)
    head(d, ox + 32, oy + 12)
    line(d, (ox + 32, oy + 17), (ox + 32, oy + 40))
    line(d, (ox + 32, oy + 22), (ox + 26, oy + 34))
    line(d, (ox + 32, oy + 22), (ox + 38, oy + 34))
    line(d, (ox + 32, oy + 40), (ox + 28, oy + 56))
    line(d, (ox + 32, oy + 40), (ox + 36, oy + 56))

    # ===== Row 0 col 1: RUN frame 2 =====
    ox, oy = at(1, 0)
    head(d, ox + 32, oy + 12)
    line(d, (ox + 32, oy + 17), (ox + 32, oy + 38))
    line(d, (ox + 32, oy + 22), (ox + 22, oy + 28))
    line(d, (ox + 32, oy + 22), (ox + 42, oy + 30))
    line(d, (ox + 32, oy + 38), (ox + 24, oy + 50), (ox + 22, oy + 56))
    line(d, (ox + 32, oy + 38), (ox + 42, oy + 44), (ox + 46, oy + 50))

    # ===== Row 0 col 2: RUN frame 3 =====
    ox, oy = at(2, 0)
    head(d, ox + 32, oy + 12)
    line(d, (ox + 32, oy + 17), (ox + 32, oy + 38))
    line(d, (ox + 32, oy + 22), (ox + 28, oy + 34))
    line(d, (ox + 32, oy + 22), (ox + 36, oy + 34))
    line(d, (ox + 32, oy + 38), (ox + 30, oy + 56))
    line(d, (ox + 32, oy + 38), (ox + 34, oy + 56))

    # ===== Row 0 col 3: RUN frame 4 =====
    ox, oy = at(3, 0)
    head(d, ox + 32, oy + 12)
    line(d, (ox + 32, oy + 17), (ox + 32, oy + 38))
    line(d, (ox + 32, oy + 22), (ox + 42, oy + 28))
    line(d, (ox + 32, oy + 22), (ox + 22, oy + 30))
    line(d, (ox + 32, oy + 38), (ox + 42, oy + 50), (ox + 46, oy + 56))
    line(d, (ox + 32, oy + 38), (ox + 22, oy + 44), (ox + 18, oy + 50))

    # ===== Row 1 col 0: JUMP frame 1 — crouch =====
    ox, oy = at(0, 1)
    head(d, ox + 32, oy + 18)
    line(d, (ox + 32, oy + 23), (ox + 32, oy + 40))
    line(d, (ox + 32, oy + 26), (ox + 24, oy + 36))
    line(d, (ox + 32, oy + 26), (ox + 40, oy + 36))
    line(d, (ox + 32, oy + 40), (ox + 24, oy + 48), (ox + 22, oy + 56))
    line(d, (ox + 32, oy + 40), (ox + 40, oy + 48), (ox + 42, oy + 56))

    # ===== Row 1 col 1: JUMP frame 2 — rising =====
    ox, oy = at(1, 1)
    head(d, ox + 32, oy + 12)
    line(d, (ox + 32, oy + 17), (ox + 32, oy + 36))
    line(d, (ox + 32, oy + 20), (ox + 26, oy + 10), (ox + 22, oy + 4))
    line(d, (ox + 32, oy + 20), (ox + 38, oy + 10), (ox + 42, oy + 4))
    line(d, (ox + 32, oy + 36), (ox + 28, oy + 46), (ox + 30, oy + 54))
    line(d, (ox + 32, oy + 36), (ox + 36, oy + 46), (ox + 34, oy + 54))

    # ===== Row 1 col 2: JUMP frame 3 — peak =====
    ox, oy = at(2, 1)
    head(d, ox + 32, oy + 14)
    line(d, (ox + 32, oy + 19), (ox + 32, oy + 38))
    line(d, (ox + 32, oy + 22), (ox + 22, oy + 18))
    line(d, (ox + 32, oy + 22), (ox + 44, oy + 22))
    line(d, (ox + 32, oy + 38), (ox + 24, oy + 46), (ox + 20, oy + 54))
    line(d, (ox + 32, oy + 38), (ox + 42, oy + 44), (ox + 48, oy + 50))

    # ===== Row 1 col 3: JUMP frame 4 — landing =====
    ox, oy = at(3, 1)
    head(d, ox + 32, oy + 16)
    line(d, (ox + 32, oy + 21), (ox + 32, oy + 40))
    line(d, (ox + 32, oy + 24), (ox + 22, oy + 30))
    line(d, (ox + 32, oy + 24), (ox + 42, oy + 30))
    line(d, (ox + 32, oy + 40), (ox + 26, oy + 48), (ox + 24, oy + 56))
    line(d, (ox + 32, oy + 40), (ox + 38, oy + 48), (ox + 40, oy + 56))

    # ===== Row 2 col 0: DUCK =====
    ox, oy = at(0, 2)
    head(d, ox + 32, oy + 30)
    line(d, (ox + 32, oy + 35), (ox + 32, oy + 46))
    line(d, (ox + 32, oy + 37), (ox + 26, oy + 44))
    line(d, (ox + 32, oy + 37), (ox + 38, oy + 44))
    line(d, (ox + 32, oy + 46), (ox + 26, oy + 50), (ox + 24, oy + 56))
    line(d, (ox + 32, oy + 46), (ox + 38, oy + 50), (ox + 40, oy + 56))

    # ===== Row 2 col 1: CRAWL frame 2 =====
    ox, oy = at(1, 2)
    head(d, ox + 46, oy + 44)
    line(d, (ox + 41, oy + 46), (ox + 20, oy + 50))
    line(d, (ox + 39, oy + 46), (ox + 50, oy + 42), (ox + 56, oy + 40))
    line(d, (ox + 28, oy + 49), (ox + 32, oy + 56))
    line(d, (ox + 20, oy + 50), (ox + 14, oy + 44), (ox + 8, oy + 46))
    line(d, (ox + 20, oy + 50), (ox + 12, oy + 56))

    # ===== Row 2 col 2: CRAWL frame 3 =====
    ox, oy = at(2, 2)
    head(d, ox + 46, oy + 44)
    line(d, (ox + 41, oy + 46), (ox + 20, oy + 50))
    line(d, (ox + 38, oy + 47), (ox + 44, oy + 54))
    line(d, (ox + 30, oy + 48), (ox + 26, oy + 54))
    line(d, (ox + 20, oy + 50), (ox + 12, oy + 50))
    line(d, (ox + 20, oy + 50), (ox + 12, oy + 56))

    # ===== Row 2 col 3: CRAWL frame 4 =====
    ox, oy = at(3, 2)
    head(d, ox + 46, oy + 44)
    line(d, (ox + 41, oy + 46), (ox + 20, oy + 50))
    line(d, (ox + 39, oy + 46), (ox + 44, oy + 54))
    line(d, (ox + 28, oy + 49), (ox + 18, oy + 54))
    line(d, (ox + 20, oy + 50), (ox + 28, oy + 44), (ox + 36, oy + 44))
    line(d, (ox + 20, oy + 50), (ox + 10, oy + 56))

    # ===== Row 3 col 0: CLIMB frame 1 — reaching up =====
    ox, oy = at(0, 3)
    head(d, ox + 28, oy + 20)
    line(d, (ox + 28, oy + 25), (ox + 28, oy + 46))
    line(d, (ox + 28, oy + 27), (ox + 34, oy + 14), (ox + 38, oy + 6))
    line(d, (ox + 28, oy + 27), (ox + 36, oy + 16), (ox + 40, oy + 10))
    line(d, (ox + 28, oy + 46), (ox + 24, oy + 56))
    line(d, (ox + 28, oy + 46), (ox + 32, oy + 56))

    # ===== Row 3 col 1: CLIMB frame 2 — gripping =====
    ox, oy = at(1, 3)
    head(d, ox + 30, oy + 22)
    line(d, (ox + 30, oy + 27), (ox + 30, oy + 48))
    line(d, (ox + 30, oy + 29), (ox + 36, oy + 16), (ox + 40, oy + 8))
    line(d, (ox + 30, oy + 29), (ox + 38, oy + 18), (ox + 42, oy + 10))
    line(d, (ox + 30, oy + 48), (ox + 26, oy + 58))
    line(d, (ox + 30, oy + 48), (ox + 34, oy + 58))

    # ===== Row 3 col 2: CLIMB frame 3 — pulling up =====
    ox, oy = at(2, 3)
    head(d, ox + 34, oy + 16)
    line(d, (ox + 34, oy + 21), (ox + 34, oy + 38))
    line(d, (ox + 34, oy + 23), (ox + 42, oy + 14), (ox + 46, oy + 8))
    line(d, (ox + 34, oy + 23), (ox + 44, oy + 14), (ox + 48, oy + 8))
    line(d, (ox + 34, oy + 38), (ox + 44, oy + 34), (ox + 50, oy + 30))
    line(d, (ox + 34, oy + 38), (ox + 30, oy + 52))

    # ===== Row 3 col 3: CLIMB frame 4 — standing on top =====
    ox, oy = at(3, 3)
    head(d, ox + 38, oy + 12)
    line(d, (ox + 38, oy + 17), (ox + 38, oy + 36))
    line(d, (ox + 38, oy + 20), (ox + 30, oy + 30))
    line(d, (ox + 38, oy + 20), (ox + 44, oy + 28))
    line(d, (ox + 38, oy + 36), (ox + 34, oy + 50), (ox + 32, oy + 56))
    line(d, (ox + 38, oy + 36), (ox + 42, oy + 50), (ox + 44, oy + 56))

    img.save(out)
    print(f"Wrote {out} ({W}x{H})")


if __name__ == "__main__":
    main()
