"""Extract clean 256x256 spritesheet from the Gemini reference image.

Approach: rather than trying to detect frame borders (which are stylised and
not perfectly axis-aligned), find connected components of dark pixels in the
image. Each stickman frame produces one large component (possibly grouped
with a small climbing-block silhouette in the CLIMB row). Cluster the 16
largest figure components into a 4-row x 4-col grid by centroid Y/X, and
crop the union bounding box of each cell.
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image

SRC = Path(r"D:\JustGames\JustParkour\.claude\worktrees\funny-chatterjee-532a10\assets\Gemini_Generated_Image_mkzv1nmkzv1nmkzv.png")
DST = Path(r"D:\JustGames\JustParkour\assets\spritesheet.png")

CELL = 64
COLS = 4
ROWS = 4

DARK_THRESHOLD = 90


def label_components(mask: np.ndarray) -> tuple[np.ndarray, int]:
    """Two-pass connected component labelling (4-connectivity) using union-find.
    Returns (label_image, num_labels). Labels are 1..N; 0 = background.
    """
    H, W = mask.shape
    labels = np.zeros((H, W), dtype=np.int32)
    parent: list[int] = [0]

    def find(x: int) -> int:
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def union(a: int, b: int) -> None:
        ra, rb = find(a), find(b)
        if ra == rb:
            return
        if ra < rb:
            parent[rb] = ra
        else:
            parent[ra] = rb

    next_label = 1
    for y in range(H):
        row = mask[y]
        for x in range(W):
            if not row[x]:
                continue
            up = labels[y - 1, x] if y > 0 else 0
            left = labels[y, x - 1] if x > 0 else 0
            if up and left:
                lbl = min(up, left)
                labels[y, x] = lbl
                if up != left:
                    union(up, left)
            elif up:
                labels[y, x] = up
            elif left:
                labels[y, x] = left
            else:
                labels[y, x] = next_label
                parent.append(next_label)
                next_label += 1

    # Resolve roots and compact labels.
    remap: dict[int, int] = {0: 0}
    final_labels = np.zeros_like(labels)
    n = 0
    for y in range(H):
        for x in range(W):
            v = labels[y, x]
            if v == 0:
                continue
            r = find(v)
            if r not in remap:
                n += 1
                remap[r] = n
            final_labels[y, x] = remap[r]
    return final_labels, n


def main() -> None:
    src = Image.open(SRC).convert("RGBA")
    arr = np.array(src)
    lum = (0.299 * arr[..., 0] + 0.587 * arr[..., 1] + 0.114 * arr[..., 2]).astype(np.uint8)
    H, W = lum.shape

    # Strip the title region: empirically the title text sits in the top ~7-8% of the image.
    title_cut = int(H * 0.085)

    dark = lum < DARK_THRESHOLD
    dark[:title_cut] = False  # ignore title text

    # Also strip the leftmost area (where row labels like "IDLE/RUN", "JUMP" sit).
    # Labels tend to start very close to x=0 and end before the first frame box (~x=180).
    # Frame boxes start around x>=140 in this Gemini export, so we mask only the very left edge
    # to remove label text without clipping into frames.
    # Instead of a fixed x cutoff (which risks clipping climb-1 block), we filter by component
    # later. Keep dark mask intact here.

    print(f"Image {W}x{H}, dark pixels: {dark.sum()}")

    # Use scipy if available (much faster). Otherwise fall back to our own labeller.
    try:
        from scipy import ndimage  # type: ignore

        labels, n = ndimage.label(dark, structure=np.ones((3, 3), dtype=int))
        print(f"Found {n} components (scipy)")
    except Exception:
        labels, n = label_components(dark)
        print(f"Found {n} components (manual)")

    # Compute bounding boxes and pixel counts for each component.
    comps: list[dict] = []
    flat = labels.ravel()
    ys, xs = np.indices(labels.shape)
    for lbl in range(1, n + 1):
        sel = labels == lbl
        cnt = int(sel.sum())
        if cnt < 400:  # filter noise & small text fragments
            continue
        ys_c = ys[sel]
        xs_c = xs[sel]
        y0, y1 = int(ys_c.min()), int(ys_c.max())
        x0, x1 = int(xs_c.min()), int(xs_c.max())
        h, w = y1 - y0 + 1, x1 - x0 + 1
        # Reject text-shaped components: wide-short ribbons (row labels) or tiny-square (badges).
        if h < 80:  # text characters are short
            continue
        if w < 30 or h < 30:
            continue
        comps.append(dict(label=lbl, count=cnt, y0=y0, y1=y1, x0=x0, x1=x1,
                          cy=(y0 + y1) / 2, cx=(x0 + x1) / 2, w=w, h=h))

    print(f"After filter: {len(comps)} components")
    for c in sorted(comps, key=lambda c: (c["cy"], c["cx"])):
        print(f"  cy={c['cy']:.0f} cx={c['cx']:.0f} w={c['w']} h={c['h']} cnt={c['count']}")

    # Cluster Y centroids into 4 rows.
    cys = sorted(c["cy"] for c in comps)
    # Row centers via 4-bin equal-frequency split using k-means-lite (1D).
    def kmeans_1d(values: list[float], k: int, iters: int = 50) -> list[float]:
        vs = sorted(values)
        # init centers as quantiles
        centers = [vs[int((i + 0.5) * len(vs) / k)] for i in range(k)]
        for _ in range(iters):
            buckets: list[list[float]] = [[] for _ in range(k)]
            for v in vs:
                bi = min(range(k), key=lambda i: abs(v - centers[i]))
                buckets[bi].append(v)
            new_centers = [sum(b) / len(b) if b else centers[i] for i, b in enumerate(buckets)]
            if new_centers == centers:
                break
            centers = new_centers
        return sorted(centers)

    row_centers = kmeans_1d(cys, ROWS)
    print(f"Row centers Y: {[round(v) for v in row_centers]}")

    # Assign each component to a row.
    for c in comps:
        c["row"] = min(range(ROWS), key=lambda i: abs(c["cy"] - row_centers[i]))

    # Within each row, cluster X centroids into 4 columns.
    grid_cells: dict[tuple[int, int], list[dict]] = {}
    for r in range(ROWS):
        row_comps = [c for c in comps if c["row"] == r]
        if not row_comps:
            print(f"WARN: row {r} has no components")
            continue
        cxs = [c["cx"] for c in row_comps]
        col_centers = kmeans_1d(cxs, COLS)
        print(f"  Row {r}: {len(row_comps)} comps, X centers: {[round(v) for v in col_centers]}")
        for c in row_comps:
            c["col"] = min(range(COLS), key=lambda i: abs(c["cx"] - col_centers[i]))
            grid_cells.setdefault((r, c["col"]), []).append(c)

    # Build the output sheet.
    sheet = Image.new("RGBA", (COLS * CELL, ROWS * CELL), (0, 0, 0, 0))

    for r in range(ROWS):
        for col in range(COLS):
            cell_comps = grid_cells.get((r, col), [])
            if not cell_comps:
                print(f"WARN: cell ({r},{col}) empty")
                continue
            # Union bounding box of all components in this cell.
            x0 = min(c["x0"] for c in cell_comps)
            y0 = min(c["y0"] for c in cell_comps)
            x1 = max(c["x1"] for c in cell_comps)
            y1 = max(c["y1"] for c in cell_comps)
            # Add a small margin and clamp.
            mg = 6
            x0 = max(0, x0 - mg); y0 = max(0, y0 - mg)
            x1 = min(W - 1, x1 + mg); y1 = min(H - 1, y1 + mg)

            # Crop a clean alpha-only render: dark strokes -> opaque, else transparent.
            crop_lum = lum[y0:y1 + 1, x0:x1 + 1].astype(np.int16)
            ch, cw = crop_lum.shape

            # Sharper alpha curve: lum<=60 -> 255 (solid), lum>=130 -> 0 (transparent),
            # linear in between. Keeps strokes solid black instead of pale gray.
            HARD = 60
            FADE = 130
            alpha = np.where(
                crop_lum <= HARD,
                255,
                np.where(
                    crop_lum >= FADE,
                    0,
                    ((FADE - crop_lum) * 255 // (FADE - HARD)),
                ),
            ).astype(np.uint8)

            # Dilate strokes by 1px so thin lines survive the ~5x downscale.
            from scipy.ndimage import maximum_filter  # type: ignore

            alpha = maximum_filter(alpha, size=3)

            rgba = np.zeros((ch, cw, 4), dtype=np.uint8)
            rgba[..., 0] = 25
            rgba[..., 1] = 25
            rgba[..., 2] = 35
            rgba[..., 3] = alpha

            cell_img = Image.fromarray(rgba, mode="RGBA")

            # Trim to non-transparent bounds.
            alpha = np.array(cell_img)[..., 3]
            ays, axs = np.where(alpha > 5)
            if len(axs) == 0:
                continue
            ay0, ay1 = int(ays.min()), int(ays.max()) + 1
            ax0, ax1 = int(axs.min()), int(axs.max()) + 1
            cell_img = cell_img.crop((ax0, ay0, ax1, ay1))

            # Scale to fit CELL (with padding) preserving aspect ratio.
            pad = 2
            avail = CELL - 2 * pad
            cw2, ch2 = cell_img.size
            scale = min(avail / cw2, avail / ch2)
            nw = max(1, int(round(cw2 * scale)))
            nh = max(1, int(round(ch2 * scale)))
            cell_img = cell_img.resize((nw, nh), Image.LANCZOS)

            # Boost alpha contrast so downsampled strokes stay solid.
            small_arr = np.array(cell_img)
            a = small_arr[..., 3].astype(np.int16)
            a = np.where(a > 20, np.minimum(255, a * 2), 0).astype(np.uint8)
            small_arr[..., 3] = a
            cell_img = Image.fromarray(small_arr, mode="RGBA")

            # Paste centred (horizontally), aligned to bottom of cell (so feet sit at bottom).
            tile = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
            ox = (CELL - nw) // 2
            oy = CELL - nh - pad
            tile.paste(cell_img, (ox, oy), cell_img)

            sheet.paste(tile, (col * CELL, r * CELL), tile)

    DST.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(DST)
    print(f"Wrote {DST} ({sheet.size[0]}x{sheet.size[1]})")


if __name__ == "__main__":
    main()
