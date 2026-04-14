"""
Memoria アプリアイコン生成スクリプト
ロゴE (Orbital) を PNG → .icns に変換する

使い方:
  python3 make_icon.py

出力:
  Memoria.icns   ← PyInstaller に渡すアイコンファイル
"""
import os
import sys
import math
import struct
import zlib
import shutil
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFilter
    import numpy as np
except ImportError:
    print("Pillowとnumpyが必要です。以下を実行してください:")
    print("  pip3 install pillow numpy")
    sys.exit(1)


def create_orbital_logo(size: int) -> Image.Image:
    """Orbital ロゴを指定サイズのRGBA画像で生成する"""

    # ── グラデーション背景 ─────────────────────────────
    # 青(下左) → 紫(中) → ピンク(上右)
    x = np.linspace(0.0, 1.0, size, dtype=np.float32)
    y = np.linspace(1.0, 0.0, size, dtype=np.float32)   # 上方向が1
    xx, yy = np.meshgrid(x, y)
    t = (xx + yy) / 2.0   # 0 = 下左, 1 = 上右

    c1 = np.array([137, 180, 250], dtype=np.float32)   # #89b4fa blue
    c2 = np.array([203, 166, 247], dtype=np.float32)   # #cba6f7 purple
    c3 = np.array([245, 194, 231], dtype=np.float32)   # #f5c2e7 pink

    t1 = np.clip(t * 2.0, 0.0, 1.0)
    t2 = np.clip((t - 0.5) * 2.0, 0.0, 1.0)
    half = t < 0.5

    rgb = np.where(half[:, :, np.newaxis],
                   c1 + (c2 - c1) * t1[:, :, np.newaxis],
                   c2 + (c3 - c2) * t2[:, :, np.newaxis]).astype(np.uint8)

    alpha = np.full((size, size, 1), 255, dtype=np.uint8)
    grad_img = Image.fromarray(np.concatenate([rgb, alpha], axis=2), 'RGBA')

    # ── 丸マスク ──────────────────────────────────────
    mask = Image.new('L', (size, size), 0)
    pad = max(1, size // 20)
    ImageDraw.Draw(mask).ellipse([pad, pad, size - pad - 1, size - pad - 1], fill=255)

    # アンチエイリアスのためにぼかし
    if size >= 64:
        mask = mask.filter(ImageFilter.GaussianBlur(radius=size // 100))

    result = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    result.paste(grad_img, mask=mask)

    # ── 内側の輪と中心点 ──────────────────────────────
    overlay = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    cx = cy = size // 2

    def ellipse(draw, cx, cy, r, fill):
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fill)

    r_outer = int(size * 0.45)
    r1 = int(size * 0.25)   # 内側リング1
    r2 = int(size * 0.125)  # 内側リング2
    r3 = int(size * 0.05)   # 中心点

    ellipse(draw, cx, cy, r1, (255, 255, 255, 38))
    ellipse(draw, cx, cy, r2, (255, 255, 255, 51))
    ellipse(draw, cx, cy, r3, (255, 255, 255, 230))

    # ── 軌道ドット (上下左右) ─────────────────────────
    orbit_r = int(size * 0.275)
    dot_r   = int(size * 0.044)
    for dx, dy in [(0, -orbit_r), (orbit_r, 0), (0, orbit_r), (-orbit_r, 0)]:
        ellipse(draw, cx + dx, cy + dy, dot_r, (255, 255, 255, 204))

    result = Image.alpha_composite(result, overlay)
    return result


def generate_iconset(dest_dir: Path, sizes=(16, 32, 64, 128, 256, 512, 1024)):
    """指定ディレクトリにアイコンセットを生成する"""
    dest_dir.mkdir(parents=True, exist_ok=True)
    for s in sizes:
        img = create_orbital_logo(s)
        img.save(dest_dir / f"icon_{s}x{s}.png")
        # @2x (Retina) は元サイズの半分を @2x と表記
        if s <= 512:
            img.save(dest_dir / f"icon_{s // 2}x{s // 2}@2x.png")
    print(f"  ✅ {len(list(dest_dir.glob('*.png')))} 枚の PNG を {dest_dir} に生成しました")


def create_icns_via_iconutil(iconset_dir: Path, output: Path) -> bool:
    """macOS の iconutil を使って .icns を生成する（Mac専用）"""
    import subprocess
    try:
        r = subprocess.run(
            ["iconutil", "-c", "icns", str(iconset_dir), "-o", str(output)],
            capture_output=True, text=True
        )
        return r.returncode == 0
    except FileNotFoundError:
        return False


def create_icns_python(iconset_dir: Path, output: Path):
    """
    Pure Python で .icns を作成する（macOS 以外でも動作）
    対応する OSType: ic07 (128) ic08 (256) ic09 (512) ic10 (1024) ic11 (16@2x=32) ic12 (32@2x=64) ic13 (128@2x=256) ic14 (256@2x=512)
    """
    SIZE_MAP = {
        "icon_16x16.png":      b"icp4",
        "icon_32x32.png":      b"icp5",
        "icon_64x64.png":      b"icp6",
        "icon_128x128.png":    b"ic07",
        "icon_256x256.png":    b"ic08",
        "icon_512x512.png":    b"ic09",
        "icon_1024x1024.png":  b"ic10",
        "icon_16x16@2x.png":   b"ic11",
        "icon_32x32@2x.png":   b"ic12",
        "icon_128x128@2x.png": b"ic13",
        "icon_256x256@2x.png": b"ic14",
    }

    entries = []
    for fname, ostype in SIZE_MAP.items():
        p = iconset_dir / fname
        if p.exists():
            data = p.read_bytes()
            entries.append((ostype, data))

    if not entries:
        raise ValueError("アイコン PNG が見つかりません")

    # .icns フォーマット: "icns" + uint32 total_size + (ostype + uint32 entry_size + data) * N
    body = b""
    for ostype, data in entries:
        entry_size = 8 + len(data)
        body += ostype + struct.pack(">I", entry_size) + data

    total_size = 8 + len(body)
    icns_data = b"icns" + struct.pack(">I", total_size) + body
    output.write_bytes(icns_data)
    print(f"  ✅ {output} を生成しました ({total_size // 1024} KB, {len(entries)} サイズ)")


def main():
    base = Path(__file__).parent
    iconset_dir = base / "Memoria.iconset"
    icns_path   = base / "Memoria.icns"

    print("🎨 Memoria アイコンを生成中...")

    # PNG 生成
    generate_iconset(iconset_dir)

    # .icns 生成: macOS の iconutil を優先、なければ pure Python
    if create_icns_via_iconutil(iconset_dir, icns_path):
        print(f"  ✅ iconutil で {icns_path} を生成しました")
    else:
        print("  iconutil が見つからないため Python で生成します...")
        create_icns_python(iconset_dir, icns_path)

    # iconset は不要なので削除
    shutil.rmtree(iconset_dir, ignore_errors=True)
    print(f"\n✨ 完了！ {icns_path}")
    print("   次のステップ: bash build_app.sh を実行してください")


if __name__ == "__main__":
    main()
