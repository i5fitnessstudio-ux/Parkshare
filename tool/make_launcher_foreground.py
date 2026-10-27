"""Generate the Android launcher (adaptive-icon) foreground for ParkShare.

Source
------
assets/images/parkshare_logo.png  (the in-app logo - NEVER modified here; it
keeps being used by the app itself).

Problem with using it directly as `adaptive_icon_foreground`:
  * the PNG is 148 x 155 and its artwork only occupies y = 33..148, so the
    logo carried ~21 % of dead transparent padding on top. flutter_launcher_icons
    scales the whole canvas, so inside the launcher icon the logo rendered
    LOW (off centre) and SMALL;
  * the canvas is not square (148 x 155) while every icon template is square,
    so the generator stretched it slightly (distortion).

Output
------
assets/images/parkshare_launcher_foreground.png

  * square 432 x 432 canvas (flutter_launcher_icons' largest density target,
    so xxxhdpi is generated 1:1 with no extra resampling);
  * artwork cropped to its alpha bounding box, then upscaled exactly 2x with a
    premultiplied-alpha LANCZOS resize -> 292 x 232: aspect ratio preserved
    EXACTLY (116/146 * 2 = 116/73 * 2/2 -> no stretching), no colour fringing
    on the transparent edges;
  * centred exactly: 70 + 292 + 70 = 432 horizontally, 100 + 232 + 100 = 432
    vertically;
  * transparent background - the white comes from `adaptive_icon_background:
    #FFFFFF`;
  * sized to stay inside the Android adaptive-icon safe zone. flutter_launcher_icons
    wraps the foreground in a 16 % inset, so the artwork ends up at
        diagonal 372.9 px / 432 px = 86.3 % of the canvas
        -> 86.3 % * 68 % * 108 dp = 63.1 dp
    which is inside the 66 dp safe circle (never clipped by round launchers)
    while still filling ~50 dp of width (46 % of the icon) so it stays clearly
    visible.

Run:  python tool/make_launcher_foreground.py
"""

from math import sqrt

from PIL import Image

SRC = "assets/images/parkshare_logo.png"
DST = "assets/images/parkshare_launcher_foreground.png"
CANVAS = 432  # px, matches flutter_launcher_icons' xxxhdpi template
SCALE = 2  # exact integer upscale -> zero distortion
ALPHA_MIN = 16  # ignore stray near-transparent pixels when cropping


def _resize_premultiplied(img: Image.Image, size: tuple[int, int]) -> Image.Image:
    """Resize RGBA while premultiplying alpha.

    The source PNG stores RGB=(0,0,0) under fully transparent pixels; resizing
    those channels naively would bleed black into the logo edges.
    """
    src = img.load()
    prem = Image.new("RGBA", img.size)
    dst = prem.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = src[x, y]
            dst[x, y] = ((r * a + 127) // 255, (g * a + 127) // 255, (b * a + 127) // 255, a)

    scaled = prem.resize(size, Image.LANCZOS)

    out = Image.new("RGBA", size)
    src2 = scaled.load()
    dst2 = out.load()
    sw, sh = size
    for y in range(sh):
        for x in range(sw):
            r, g, b, a = src2[x, y]
            if a == 0:
                dst2[x, y] = (0, 0, 0, 0)
                continue

            def un(c: int) -> int:
                v = (c * 255 + a // 2) // a
                return 0 if v < 0 else 255 if v > 255 else v

            dst2[x, y] = (un(r), un(g), un(b), a)
    return out


def main() -> None:
    logo = Image.open(SRC).convert("RGBA")

    alpha = logo.getchannel("A").point(lambda a: 255 if a >= ALPHA_MIN else 0)
    left, top, right, bottom = alpha.getbbox()
    art = logo.crop((left, top, right, bottom))
    print(f"source {logo.size}, artwork bbox {(left, top, right, bottom)} -> {art.size}")

    target = (art.width * SCALE, art.height * SCALE)
    art = _resize_premultiplied(art, target)
    print(f"upscaled {SCALE}x -> {art.size} (aspect preserved)")

    if target[0] > CANVAS or target[1] > CANVAS:
        raise SystemExit(f"artwork {target} does not fit a {CANVAS} canvas")

    x = (CANVAS - target[0]) // 2
    y = (CANVAS - target[1]) // 2
    if (CANVAS - target[0]) % 2 or (CANVAS - target[1]) % 2:
        raise SystemExit("canvas centre would be off by a pixel - pick even sizes")

    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    canvas.paste(art, (x, y), art)
    canvas.save(DST)

    # --- verification ---------------------------------------------------
    check = Image.open(DST).convert("RGBA")
    bbox = check.getchannel("A").point(lambda a: 255 if a > 0 else 0).getbbox()
    bw, bh = bbox[2] - bbox[0], bbox[3] - bbox[1]
    cx, cy = (bbox[0] + bbox[2]) / 2, (bbox[1] + bbox[3]) / 2
    inset = 0.16  # flutter_launcher_icons adaptive_icon_foreground_inset default
    diag_dp = sqrt(bw**2 + bh**2) / CANVAS * (1 - 2 * inset) * 108
    print(f"wrote {DST}: canvas {check.size}, artwork bbox {bbox}")
    print(
        f"centre=({cx:.1f}, {cy:.1f}) vs canvas centre ({CANVAS / 2}, {CANVAS / 2}) | "
        f"pad x={bbox[0]}/{CANVAS - bbox[2]} y={bbox[1]}/{CANVAS - bbox[3]}"
    )
    print(
        f"on-icon size: {bw / CANVAS * (1 - 2 * inset) * 108:.1f} dp wide, "
        f"{bh / CANVAS * (1 - 2 * inset) * 108:.1f} dp tall, "
        f"diagonal {diag_dp:.1f} dp (safe zone 66 dp)"
    )
    if abs(cx - CANVAS / 2) > 1 or abs(cy - CANVAS / 2) > 1:
        raise SystemExit("artwork is not centred")
    if diag_dp > 66:
        raise SystemExit("artwork exceeds the 66 dp adaptive-icon safe zone")


if __name__ == "__main__":
    main()
