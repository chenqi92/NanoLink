#!/usr/bin/env python3
"""Build NanoOps mobile icon assets from the approved logo source.

The source artwork is a blue mark on an almost-white square.  This script
extracts that mark without changing its geometry, then creates the platform
variants required by modern iOS and Android launchers.

Requires Pillow 10 or newer.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageOps


REPO_ROOT = Path(__file__).resolve().parents[2]
BRANDING_DIR = REPO_ROOT / "apps" / "branding"
IOS_ICON_DIR = (
    REPO_ROOT
    / "apps"
    / "ios"
    / "NanoLink"
    / "Assets.xcassets"
    / "AppIcon.appiconset"
)
ANDROID_RES_DIR = REPO_ROOT / "apps" / "android" / "app" / "src" / "main" / "res"

SOURCE_LOGO = BRANDING_DIR / "nanoops-logo-source.png"


def _hex_color(value: str) -> tuple[int, int, int]:
    value = value.removeprefix("#")
    if len(value) != 6:
        raise ValueError(f"Expected a six-digit RGB color, got {value!r}")
    return tuple(int(value[index : index + 2], 16) for index in (0, 2, 4))


def _extract_mark_mask(source_path: Path) -> Image.Image:
    """Extract the blue mark's antialiased alpha from its pale background."""

    source = Image.open(source_path).convert("RGB")
    red, green, blue = source.split()

    # For a blue foreground composited over white, 255 - min(R, G) closely
    # recovers the original coverage.  Suppress neutral/off-white background
    # pixels by requiring a small amount of blue dominance as well.
    coverage = ImageChops.invert(ImageChops.darker(red, green))
    blue_dominance = ImageChops.subtract(blue, ImageChops.lighter(red, green))
    dominance_gate = blue_dominance.point(lambda value: 255 if value >= 3 else 0)
    mask = ImageChops.multiply(coverage, dominance_gate)
    mask = mask.point(lambda value: 0 if value < 4 else min(255, round(value * 1.08)))

    bounds = mask.point(lambda value: 255 if value >= 8 else 0).getbbox()
    if bounds is None:
        raise RuntimeError(f"No blue logo mark found in {source_path}")
    return mask.crop(bounds)


def _vertical_gradient(
    size: tuple[int, int], top: str, bottom: str
) -> Image.Image:
    top_rgb = _hex_color(top)
    bottom_rgb = _hex_color(bottom)
    height = max(size[1], 1)
    rows: list[tuple[int, int, int]] = []
    for y in range(height):
        amount = y / max(height - 1, 1)
        rows.append(
            tuple(
                round(start + (end - start) * amount)
                for start, end in zip(top_rgb, bottom_rgb)
            )
        )
    strip = Image.new("RGB", (1, height))
    strip.putdata(rows)
    return strip.resize(size)


def _radial_background(size: int, center: str, edge: str) -> Image.Image:
    radial = Image.radial_gradient("L").resize((size, size), Image.Resampling.LANCZOS)
    return ImageOps.colorize(radial, black=center, white=edge).convert("RGBA")


def _mark_layer(
    source_mask: Image.Image,
    canvas_size: int,
    target_width: int,
    top: str,
    bottom: str,
    vertical_offset: int = 0,
) -> Image.Image:
    scale = target_width / source_mask.width
    target_height = max(1, round(source_mask.height * scale))
    resized_mask = source_mask.resize(
        (target_width, target_height), Image.Resampling.LANCZOS
    )
    mark = _vertical_gradient((target_width, target_height), top, bottom).convert("RGBA")
    mark.putalpha(resized_mask)

    layer = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    x = (canvas_size - target_width) // 2
    y = (canvas_size - target_height) // 2 + vertical_offset
    layer.alpha_composite(mark, (x, y))
    return layer


def _save(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG", optimize=True)
    print(path.relative_to(REPO_ROOT))


def _rounded_preview(icon: Image.Image, size: int) -> Image.Image:
    icon = icon.convert("RGBA").resize((size, size), Image.Resampling.LANCZOS)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, size - 1, size - 1), radius=round(size * 0.22), fill=255
    )
    icon.putalpha(ImageChops.multiply(icon.getchannel("A"), mask))
    return icon


def main() -> None:
    source_mask = _extract_mark_mask(SOURCE_LOGO)

    # iOS uses a full 1024 px icon for the default appearance.  Apple requests
    # a transparent background for Dark and a grayscale image for Tinted.
    ios_light_mark = _mark_layer(
        source_mask, 1024, 760, "#086CFF", "#074FEF", vertical_offset=-4
    )
    ios_light = _radial_background(1024, "#EFF6FF", "#FFFFFF")
    ios_light.alpha_composite(ios_light_mark)

    ios_dark = _mark_layer(
        source_mask, 1024, 760, "#15C8FF", "#0870FF", vertical_offset=-4
    )
    ios_tinted = _mark_layer(
        source_mask, 1024, 760, "#FFFFFF", "#D9D9D9", vertical_offset=-4
    )

    _save(ios_light.convert("RGB"), IOS_ICON_DIR / "NanoLink-AppIcon-1024.png")
    _save(ios_dark, IOS_ICON_DIR / "NanoLink-AppIcon-Dark-1024.png")
    _save(ios_tinted, IOS_ICON_DIR / "NanoLink-AppIcon-Tinted-1024.png")

    # Android adaptive icon layers are 108 dp.  A 432 px master maps to xxxhdpi;
    # the mark stays inside the official 66 dp safe zone (264 px here).
    android_light = _mark_layer(source_mask, 432, 264, "#086CFF", "#074FEF")
    android_dark = _mark_layer(source_mask, 432, 264, "#15C8FF", "#0870FF")
    android_mono = _mark_layer(source_mask, 432, 264, "#FFFFFF", "#FFFFFF")
    _save(
        android_light,
        ANDROID_RES_DIR / "drawable-nodpi" / "ic_launcher_foreground.png",
    )
    _save(
        android_dark,
        ANDROID_RES_DIR / "drawable-night-nodpi" / "ic_launcher_foreground.png",
    )
    _save(
        android_mono,
        ANDROID_RES_DIR / "drawable-nodpi" / "ic_launcher_monochrome.png",
    )

    # Keep reviewable, platform-neutral masters next to the approved source.
    dark_preview = _radial_background(1024, "#0B2C69", "#050E22")
    dark_preview.alpha_composite(ios_dark)
    tinted_preview = Image.new("RGBA", (1024, 1024), "#30343B")
    tinted_preview.alpha_composite(ios_tinted)
    _save(ios_light.convert("RGB"), BRANDING_DIR / "nanoops-icon-light-1024.png")
    _save(dark_preview.convert("RGB"), BRANDING_DIR / "nanoops-icon-dark-1024.png")
    _save(tinted_preview.convert("L"), BRANDING_DIR / "nanoops-icon-tinted-1024.png")
    _save(
        ios_light.convert("RGB").resize((512, 512), Image.Resampling.LANCZOS),
        BRANDING_DIR / "nanoops-playstore-512.png",
    )

    # Contact sheet for a quick visual check without altering deliverable files.
    preview = Image.new("RGB", (1000, 360), "#171A21")
    light_tile = _rounded_preview(ios_light, 280)
    dark_tile = _rounded_preview(dark_preview, 280)
    tinted_tile = _rounded_preview(tinted_preview, 280)
    preview.paste(light_tile, (40, 40), light_tile)
    preview.paste(dark_tile, (360, 40), dark_tile)
    preview.paste(tinted_tile, (680, 40), tinted_tile)
    _save(preview, BRANDING_DIR / "nanoops-icon-preview.png")


if __name__ == "__main__":
    main()
