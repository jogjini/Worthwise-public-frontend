#!/usr/bin/env python3
"""Builds the App Store marketing frames from the raw captures.

raw/<device>/NN_*.png  ->  final/<device>/NN_*.png (1320 x 2868, opaque PNG)

Each frame is the HTML template filled in and rendered with headless Chrome,
then flattened with ImageMagick (Chrome's PNGs carry an alpha channel, which
App Store Connect rejects). Headlines and layout: screenshots/PLAN.md.
"""
import html
import pathlib
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
SIZE = (1320, 2868)

# (file stem, headline with *accent word*, sub-caption, footer?, tag mark?, veil?)
# veil: the frame is scrolled, so content shows through under the status bar;
# cover it with the clean status bar from 01 (same 9:41 override, same background).
FRAMES = [
    ("01_Value", "See what it's<br>*worth*", "Snap a photo. Get a value range.", True, True, False),
    ("02_SoldPrices", "Backed by real<br>*sold* prices", "Last 90 days. Chart and sales with Pro.", True, False, True),
    ("03_Collection", "Your finds,<br>all in one place", "Folders, search and spreadsheet export.", False, False, True),
    ("04_Correct", "Wrong match?<br>Correct it", "Type what you know, then scan again.", False, False, False),
    ("05_Categories", "Cards, coins,<br>antiques & more", "Plus vinyl, comics, watches and toys.", False, False, True),
    ("06_Listings", "Check it<br>before you buy", "Listings and sold prices, with Pro.", True, False, True),
]
VEIL_SOURCE = "01_Value.png"

# The Tag mark, path copied from branding/final/AppIcon.svg (viewBox = the tag's bounds there).
MARK = ('<svg class="mark" viewBox="285.26 174.08 453.48 634.88">'
        '<path fill="#FFFFFF" fill-rule="evenodd" d="M512 174.08L583.91 174.08A45.35 45.35 0 0 1 615.98 187.36L725.46 296.84A45.35 45.35 0 0 1 738.74 328.91L738.74 718.26A90.7 90.7 0 0 1 648.05 808.96L375.95 808.96A90.7 90.7 0 0 1 285.26 718.26L285.26 328.91A45.35 45.35 0 0 1 298.54 296.84L408.02 187.36A45.35 45.35 0 0 1 440.09 174.08ZM398.63 355.47A113.37 113.37 0 1 0 625.37 355.47A113.37 113.37 0 1 0 398.63 355.47ZM463.63 355.47A48.37 48.37 0 1 0 560.37 355.47A48.37 48.37 0 1 0 463.63 355.47Z"/></svg>')


def headline(text):
    # Escape, keep the hand-placed <br>, and colour the one *accent* word.
    parts = html.escape(text).replace("&lt;br&gt;", "<br>").split("*")
    assert len(parts) in (1, 3), f"one accent word at most: {text}"
    return parts[0] if len(parts) == 1 else f"{parts[0]}<em>{parts[1]}</em>{parts[2]}"


def render(raw, out, title, sub, foot, mark, veil):
    page = (HERE / "frame.html").read_text()
    page = (page.replace("{{MARK}}", MARK if mark else "")
                .replace("{{HEADLINE}}", headline(title))
                .replace("{{SUB}}", f'<p class="sub">{html.escape(sub)}</p>' if sub else "")
                .replace("{{SCREEN}}", raw.as_uri())
                .replace("{{VEIL}}", f'<div class="veil" style="background-image:url({(raw.parent / VEIL_SOURCE).as_uri()})"></div>' if veil else "")
                .replace("{{FOOT}}", '<div class="foot">Estimates, not appraisals.</div>' if foot else ""))
    # The page sits next to the template so the font's relative URL resolves.
    with tempfile.NamedTemporaryFile("w", suffix=".html", dir=HERE, delete=False) as f:
        f.write(page)
        tmp = pathlib.Path(f.name)
    try:
        shot = out.with_suffix(".chrome.png")
        subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                        "--force-device-scale-factor=1", "--allow-file-access-from-files",
                        "--run-all-compositor-stages-before-draw",  # no half-painted tiles
                        "--virtual-time-budget=3000",  # lets the web font load before the capture
                        f"--window-size={SIZE[0]},{SIZE[1]}", f"--screenshot={shot}", tmp.as_uri()],
                       check=True, capture_output=True)
        subprocess.run(["magick", shot, "-background", "#1B2585", "-alpha", "remove", "-alpha", "off",
                        "-crop", f"{SIZE[0]}x{SIZE[1]}+0+0", "+repage", out], check=True)
        shot.unlink()
    finally:
        tmp.unlink()
    # Self-check: exact size, no alpha channel.
    info = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", "-g", "hasAlpha", out],
                          check=True, capture_output=True, text=True).stdout
    assert f"pixelWidth: {SIZE[0]}" in info and f"pixelHeight: {SIZE[1]}" in info and "hasAlpha: no" in info, info
    # ...and fully painted: the bottom corners are the background colour.
    corners = subprocess.run(["magick", out, "-format", "%[pixel:p{5,2862}] %[pixel:p{1314,2862}]", "info:"],
                             check=True, capture_output=True, text=True).stdout
    assert corners == "srgb(11,15,61) srgb(11,15,61)", f"{out.name}: unpainted area ({corners})"


def main():
    built = 0
    for device_dir in sorted((ROOT / "raw").iterdir()):
        if not device_dir.is_dir():
            continue
        out_dir = ROOT / "final" / device_dir.name
        out_dir.mkdir(parents=True, exist_ok=True)
        for stem, title, sub, foot, mark, veil in FRAMES:
            raw = device_dir / f"{stem}.png"
            if not raw.exists():
                sys.exit(f"missing raw capture: {raw}")
            render(raw, out_dir / f"{stem}.png", title, sub, foot, mark, veil)
            built += 1
            print(f"  {device_dir.name}/{stem}.png")
    if not built:
        sys.exit("no raw captures in screenshots/raw/")


if __name__ == "__main__":
    main()
