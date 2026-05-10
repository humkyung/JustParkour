"""Piskel 작업물을 마스터 ``assets/spritesheet.png``로 빌드합니다.

각 애니메이션마다 다음 두 가지 입력 형식을 지원합니다 (.piskel 우선).

- ``assets/piskel/<name>.piskel`` (1순위)
    Piskel 네이티브 프로젝트 파일 (JSON으로 감싼 base64 PNG). 평소 워크플로우.
- ``assets/piskel/<name>.png`` (2순위, 폴백)
    Piskel 또는 다른 도구에서 export한 가로 strip PNG.
    (1×N 셀, 즉 ``N * 64 × 64`` px)

레이아웃 (반드시 main.lua의 ``setupAnimations()``와 일치해야 합니다)
  Row 0: idle (col 0)        | run frames 2..4 (cols 1..3)
  Row 1: jump frames 1..4 (cols 0..3)
  Row 2: duck (col 0)        | crawl frames 2..4 (cols 1..3)
  Row 3: climb frames 1..4 (cols 0..3)

각 셀은 64x64 px, 시트 전체는 256x256 px (4 cols x 4 rows).

사용법
  python scripts/piskel_to_spritesheet.py
      # assets/piskel/ 안에서 발견되는 .piskel 또는 .png를 읽어
      # assets/spritesheet.png를 새로 만듭니다 (없는 애니메이션은 투명).
  python scripts/piskel_to_spritesheet.py --keep-existing
      # 기존 spritesheet.png를 베이스로 두고, 발견된 입력만 덮어씁니다.
      # (특정 애니메이션 한두 개만 갱신할 때 편리)

각 애니메이션의 입력 strip의 기대 크기 (가로 x 세로):
  idle  : 64x64    (1 frame)
  run   : 192x64   (3 frames)
  jump  : 256x64   (4 frames)
  duck  : 64x64    (1 frame)
  crawl : 192x64   (3 frames)
  climb : 256x64   (4 frames)

크기가 어긋나면 스크립트는 오류 메시지를 내고 중단합니다.
"""
from __future__ import annotations

import argparse
import base64
import io
import json
from pathlib import Path

from PIL import Image

CELL = 64
COLS = 4
ROWS = 4
SHEET_W, SHEET_H = COLS * CELL, ROWS * CELL

ROOT = Path(__file__).resolve().parent.parent
PISKEL_DIR = ROOT / "assets" / "piskel"
OUTPUT = ROOT / "assets" / "spritesheet.png"

# 애니메이션 -> (row, col_start, num_frames).
# 입력은 가로 방향으로 num_frames개의 64x64 셀이 이어진 strip이어야 하며,
# 각 프레임은 마스터 시트의 (row, col_start), (row, col_start+1), ... 위치에 배치됩니다.
LAYOUT: dict[str, tuple[int, int, int]] = {
    "idle":  (0, 0, 1),
    "run":   (0, 1, 3),
    "jump":  (1, 0, 4),
    "duck":  (2, 0, 1),
    "crawl": (2, 1, 3),
    "climb": (3, 0, 4),
}


def decode_piskel(path: Path) -> Image.Image:
    """``.piskel`` 파일을 읽어 가로 strip Image를 반환합니다.

    우리 워크플로우는 단일 chunk + 가로 strip(layout = ``[[0],[1],...]``) 형태만
    지원합니다. 다른 layout은 명시적 오류로 거부합니다.
    """
    with path.open("r", encoding="utf-8") as f:
        outer = json.load(f)
    p = outer.get("piskel") or {}
    layers = p.get("layers") or []
    if len(layers) == 0:
        raise ValueError(f"{path.name}: layers가 비어 있음")

    # piskel.layers는 JSON 문자열의 배열이므로 한 번 더 파싱.
    layer = json.loads(layers[0])
    chunks = layer.get("chunks") or []
    if len(chunks) != 1:
        raise ValueError(f"{path.name}: 단일 chunk만 지원 (현재 {len(chunks)}개)")

    chunk = chunks[0]
    layout = chunk.get("layout") or []
    frame_count = layer.get("frameCount") or 0

    if len(layout) != frame_count:
        raise ValueError(
            f"{path.name}: layout column 수 {len(layout)} != frameCount {frame_count}"
        )
    for col_idx, column in enumerate(layout):
        if len(column) != 1 or column[0] != col_idx:
            raise ValueError(
                f"{path.name}: 지원하지 않는 layout (단일 행 가로 strip만 가능)"
            )

    b64 = chunk.get("base64PNG", "")
    if b64.startswith("data:image/png;base64,"):
        b64 = b64.split(",", 1)[1]
    png_binary = base64.b64decode(b64)
    return Image.open(io.BytesIO(png_binary)).convert("RGBA")


def load_strip(name: str) -> tuple[Image.Image, str] | None:
    """애니메이션 이름에 해당하는 strip 이미지를 찾아 반환합니다.

    ``assets/piskel/<name>.piskel``을 우선 시도하고, 없으면 ``<name>.png``를 시도합니다.
    둘 다 없으면 ``None``을 반환합니다. 두 번째 반환값은 출처(piskel/png) 표시.
    """
    piskel_path = PISKEL_DIR / f"{name}.piskel"
    png_path = PISKEL_DIR / f"{name}.png"
    if piskel_path.exists():
        return decode_piskel(piskel_path), "piskel"
    if png_path.exists():
        return Image.open(png_path).convert("RGBA"), "png"
    return None


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--keep-existing",
        action="store_true",
        help=(
            "기존 assets/spritesheet.png를 베이스로 두고, "
            "발견된 입력만 덮어씁니다. (없으면 빈 시트로 시작)"
        ),
    )
    args = parser.parse_args()

    if args.keep_existing and OUTPUT.exists():
        sheet = Image.open(OUTPUT).convert("RGBA")
        if sheet.size != (SHEET_W, SHEET_H):
            print(
                f"warn: 기존 {OUTPUT.name}는 {sheet.size}, "
                f"기대 크기 ({SHEET_W}, {SHEET_H})와 다름 — 빈 시트로 새로 시작",
            )
            sheet = Image.new("RGBA", (SHEET_W, SHEET_H), (0, 0, 0, 0))
    else:
        sheet = Image.new("RGBA", (SHEET_W, SHEET_H), (0, 0, 0, 0))

    if not PISKEL_DIR.exists():
        print(
            f"error: {PISKEL_DIR}가 없습니다. "
            f"디렉토리를 만들고 .piskel 또는 .png strip을 두세요.",
        )
        return 1

    placed = 0
    skipped = 0
    for anim, (row, col_start, n_frames) in LAYOUT.items():
        result = load_strip(anim)
        if result is None:
            print(f"  skip:   {anim:6s} ({anim}.piskel/{anim}.png 모두 없음)")
            skipped += 1
            continue

        strip, source = result
        expected = (n_frames * CELL, CELL)
        if strip.size != expected:
            print(
                f"  error:  {anim}.{source} 크기가 {strip.size} — "
                f"{expected} ({n_frames} frames x {CELL}px) 이어야 합니다.",
            )
            return 1

        for i in range(n_frames):
            frame = strip.crop((i * CELL, 0, (i + 1) * CELL, CELL))
            x = (col_start + i) * CELL
            y = row * CELL
            sheet.paste(frame, (x, y), frame)

        cols_str = (
            f"col {col_start}"
            if n_frames == 1
            else f"cols {col_start}..{col_start + n_frames - 1}"
        )
        print(f"  ok:     {anim:6s} ({source:6s}) -> row {row}, {cols_str}")
        placed += 1

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(OUTPUT)
    print()
    print(f"wrote {OUTPUT.relative_to(ROOT)} ({placed} placed, {skipped} skipped)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
