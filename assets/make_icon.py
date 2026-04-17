"""Generate iOS/macOS app icons for Gomoku.

Design: wood-grain board background with a partial 5-in-a-row
pattern showing 3 black stones + 2 white stones in a diagonal line.
The 5 stones evoke "五子连珠" (five-in-a-row) directly.

Outputs 1024, 512, 180, 167, 152, 120, 76 PNG sizes at assets/icon_*.png.
"""
import os
import math
from PIL import Image, ImageDraw, ImageFilter

ASSETS_DIR = os.path.dirname(os.path.abspath(__file__))
SIZES = [1024, 512, 180, 167, 152, 120, 76]

# Palette (matches in-game wood theme)
WOOD_BASE = (194, 153, 107)    # warm wood
WOOD_DARK = (158, 119, 78)     # deeper grain
GRID_LINE = (68, 42, 18)       # dark line
STONE_BLACK = (28, 28, 28)
STONE_WHITE = (250, 248, 242)


def render_icon(size: int) -> Image.Image:
    img = Image.new("RGB", (size, size), WOOD_BASE)
    draw = ImageDraw.Draw(img)

    # Subtle wood grain — horizontal bands
    for y in range(0, size, max(2, size // 256)):
        # sinusoidal variation
        alpha = 0.5 + 0.5 * math.sin(y * 0.12)
        shade_r = int(WOOD_BASE[0] * (1 - 0.06 * alpha) + WOOD_DARK[0] * 0.06 * alpha)
        shade_g = int(WOOD_BASE[1] * (1 - 0.06 * alpha) + WOOD_DARK[1] * 0.06 * alpha)
        shade_b = int(WOOD_BASE[2] * (1 - 0.06 * alpha) + WOOD_DARK[2] * 0.06 * alpha)
        draw.line([(0, y), (size, y)], fill=(shade_r, shade_g, shade_b), width=1)

    # Draw a 4x4 grid cell background (not full 15x15 — just enough
    # context to show "this is a board")
    grid_cells = 5
    margin = size * 0.14
    cell = (size - 2 * margin) / (grid_cells - 1)
    line_w = max(2, int(size * 0.008))

    for i in range(grid_cells):
        x = margin + i * cell
        draw.line([(x, margin), (x, size - margin)], fill=GRID_LINE, width=line_w)
        draw.line([(margin, x), (size - margin, x)], fill=GRID_LINE, width=line_w)

    # Place 5 stones in a diagonal: 3 black interleaved with 2 white
    # showing that black just got 5-in-a-row (the winning move)
    # Positions (col, row) in the 5x5 subgrid:
    diagonal = [(0, 0), (1, 1), (2, 2), (3, 3), (4, 4)]
    colors = [STONE_BLACK, STONE_WHITE, STONE_BLACK, STONE_WHITE, STONE_BLACK]

    stone_radius = cell * 0.44

    for (col, row), color in zip(diagonal, colors):
        cx = margin + col * cell
        cy = margin + row * cell

        # Shadow
        shadow_offset = max(1, int(size * 0.006))
        shadow = Image.new("RGBA", (int(stone_radius * 2.4), int(stone_radius * 2.4)), (0, 0, 0, 0))
        sd = ImageDraw.Draw(shadow)
        sr = stone_radius * 1.05
        sd.ellipse(
            [
                (stone_radius * 0.15, stone_radius * 0.15),
                (stone_radius * 0.15 + 2 * sr, stone_radius * 0.15 + 2 * sr),
            ],
            fill=(0, 0, 0, 110),
        )
        shadow = shadow.filter(ImageFilter.GaussianBlur(radius=max(1, size // 200)))
        img.paste(
            shadow,
            (int(cx - stone_radius - shadow_offset), int(cy - stone_radius - shadow_offset)),
            shadow,
        )

        # Stone body
        draw.ellipse(
            [(cx - stone_radius, cy - stone_radius), (cx + stone_radius, cy + stone_radius)],
            fill=color,
        )

        # Highlight (top-left, subtle radial gradient)
        highlight_r = stone_radius * 0.32
        hx = cx - stone_radius * 0.38
        hy = cy - stone_radius * 0.38
        # Oversize the canvas so the Gaussian blur can fade to true zero alpha
        pad = int(size * 0.04)
        box_size = int(highlight_r * 2) + pad * 2
        highlight = Image.new("RGBA", (box_size, box_size), (0, 0, 0, 0))
        hd = ImageDraw.Draw(highlight)
        if color == STONE_BLACK:
            hl_color = (120, 120, 120, 130)
        else:
            hl_color = (255, 255, 255, 200)
        hd.ellipse(
            [(pad, pad), (pad + highlight_r * 2, pad + highlight_r * 2)],
            fill=hl_color,
        )
        highlight = highlight.filter(ImageFilter.GaussianBlur(radius=max(2, size // 60)))
        img.paste(
            highlight,
            (int(hx - highlight_r - pad), int(hy - highlight_r - pad)),
            highlight,
        )

    return img


def main():
    # Generate a high-res master then resize down for crispness
    master = render_icon(1024)
    for size in SIZES:
        if size == 1024:
            out = master
        else:
            out = master.resize((size, size), Image.Resampling.LANCZOS)
        path = os.path.join(ASSETS_DIR, f"icon_{size}.png")
        out.save(path, "PNG")
        print(f"Wrote {path} ({size}x{size})")


if __name__ == "__main__":
    main()
