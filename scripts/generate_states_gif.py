#!/usr/bin/env python3
"""Render docs/assets/states.gif — animated cheat-sheet of the 7 VibeLight states.

Each cell shows the state name + a colored "lamp" that animates with the same
effect the app drives for that state (solid / breathe / blink / blink-then-solid).
The loop is 6 s @ 20 fps = 120 frames. Run from repo root:

    python3 scripts/generate_states_gif.py
"""
from __future__ import annotations

import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

OUTPUT = Path(__file__).resolve().parent.parent / "docs" / "assets" / "states.gif"
DURATION_S = 6.0
FPS = 15
N_FRAMES = int(DURATION_S * FPS)

# Colors come from Resources/config.example.json (slightly punched up so the GIF
# renders crisply against the dark background).
STATES = [
    ("IDLE",       (143,  92, 191), "solid"),
    ("WORKING",    ( 60, 140, 255), "breathe"),
    ("COMPACTING", (240, 220,  70), "breathe"),
    ("WAITING",    (255, 150,  40), "blink_then_solid"),
    ("NEEDS_AUTH", (255,  60,  60), "solid"),
    ("ERROR",      (255,  60,  60), "blink"),
    ("DONE",       (143,  92, 191), "blink_then_solid"),
]

CELL_W, CELL_H = 130, 180
W = CELL_W * len(STATES)
H = CELL_H
BG = (22, 22, 26)
LABEL = (210, 210, 215)
CIRCLE_CENTER_Y = 110
CIRCLE_R = 30
GLOW_R_MAX = 60
DIM_FLOOR = 0.18   # how dim the "off" portion of blink/breathe goes (vs. fully off)


def _font(size: int) -> ImageFont.ImageFont:
    for candidate in (
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/Library/Fonts/Arial.ttf",
    ):
        try:
            return ImageFont.truetype(candidate, size)
        except OSError:
            continue
    return ImageFont.load_default()


def intensity(effect: str, t: float) -> float:
    """Return brightness multiplier 0..1 at loop-time t (seconds in [0, DURATION_S))."""
    if effect == "solid":
        return 1.0
    if effect == "breathe":
        # 2 s sine wave, dimmest = DIM_FLOOR, brightest = 1.0
        phase = (t % 2.0) / 2.0
        sine = 0.5 + 0.5 * math.sin(2.0 * math.pi * phase - math.pi / 2.0)
        return DIM_FLOOR + (1.0 - DIM_FLOOR) * sine
    if effect == "blink":
        # 1 Hz square wave
        return 1.0 if (t % 1.0) < 0.5 else DIM_FLOOR
    if effect == "blink_then_solid":
        # 0–3 s blink at 2 Hz, then solid 3–6 s. Captures the "blink then settle" UX.
        if t < 3.0:
            return 1.0 if (t % 0.5) < 0.25 else DIM_FLOOR
        return 1.0
    return 1.0


def blend(rgb: tuple[int, int, int], alpha: float) -> tuple[int, int, int]:
    """Multiply rgb toward the background by (1 - alpha)."""
    r = int(BG[0] + (rgb[0] - BG[0]) * alpha)
    g = int(BG[1] + (rgb[1] - BG[1]) * alpha)
    b = int(BG[2] + (rgb[2] - BG[2]) * alpha)
    return (r, g, b)


def draw_cell(
    img: Image.Image,
    draw: ImageDraw.ImageDraw,
    x: int,
    label: str,
    color: tuple[int, int, int],
    brightness: float,
    label_font: ImageFont.ImageFont,
) -> None:
    cx = x + CELL_W // 2
    cy = CIRCLE_CENTER_Y

    # Glow halo: concentric rings fading out from the center.
    rings = 12
    for i in range(rings, 0, -1):
        r = int(CIRCLE_R + (GLOW_R_MAX - CIRCLE_R) * (i / rings))
        # Halo alpha falls off with i^2; scaled by current brightness.
        ring_alpha = (1.0 - (i / rings)) ** 2 * 0.55 * brightness
        ring_color = blend(color, ring_alpha)
        draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=ring_color)

    # Bright core.
    core_color = blend(color, max(brightness, 0.05))
    draw.ellipse(
        (cx - CIRCLE_R, cy - CIRCLE_R, cx + CIRCLE_R, cy + CIRCLE_R),
        fill=core_color,
    )

    # Label centered under the lamp.
    text_bbox = draw.textbbox((0, 0), label, font=label_font)
    text_w = text_bbox[2] - text_bbox[0]
    draw.text((cx - text_w / 2, 160), label, fill=LABEL, font=label_font)


def render_frame(frame_idx: int) -> Image.Image:
    t = (frame_idx / N_FRAMES) * DURATION_S
    img = Image.new("RGB", (W, H), BG)
    draw = ImageDraw.Draw(img)
    font = _font(14)
    for i, (name, color, effect) in enumerate(STATES):
        brightness = intensity(effect, t)
        draw_cell(img, draw, i * CELL_W, name, color, brightness, font)
    return img


def main() -> None:
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    frames = [render_frame(i) for i in range(N_FRAMES)]
    # Quantize each frame to a shared 256-color palette to keep the GIF small
    # while preserving smooth gradients in the glow halo.
    palette_source = frames[N_FRAMES // 4]  # mid-cycle frame has good color coverage
    palette_img = palette_source.convert("P", palette=Image.ADAPTIVE, colors=256)
    quantized = [f.quantize(palette=palette_img, dither=Image.FLOYDSTEINBERG) for f in frames]

    quantized[0].save(
        OUTPUT,
        save_all=True,
        append_images=quantized[1:],
        duration=int(1000 / FPS),
        loop=0,
        optimize=True,
        disposal=2,
    )
    print(f"Wrote {OUTPUT} ({len(frames)} frames, {W}x{H}, {FPS} fps)")


if __name__ == "__main__":
    main()
