#!/usr/bin/env python3
"""Generates the printable reference card PDF from assets/card_layout.json.

The app and this script read the same layout file, so patch positions and
colors always agree. Run from the repository root:

    pip install reportlab
    python3 tools/make_card.py            # US Letter (default)
    python3 tools/make_card.py --a4

Output: assets/reference_card.pdf (bundled in the app) and docs/reference_card.pdf.
"""
import argparse
import json
import shutil
from pathlib import Path

from reportlab.lib.pagesizes import A4, letter
from reportlab.lib.units import mm
from reportlab.pdfgen import canvas

ROOT = Path(__file__).resolve().parent.parent
layout = json.loads((ROOT / "assets/card_layout.json").read_text())


def draw_card(c, ox, oy):
    """Draws one card with its top-left corner at page point (ox, oy)."""
    W, H = layout["width"], layout["height"]

    def P(x, y):  # card mm (origin top-left, y down) -> page points
        return ox + x * mm, oy - y * mm

    # Cut line
    c.setStrokeGray(0.6)
    c.setLineWidth(0.4)
    c.setDash(2, 2)
    x0, y0 = P(0, H)
    c.rect(x0, y0, W * mm, H * mm, stroke=1, fill=0)
    c.setDash()

    # Corner marks: black squares with a small white center dot, to help
    # tapping the exact center. Numbered 1-4 in the order the app asks for.
    fs = layout["fiducialSize"]
    for i, (fx, fy) in enumerate(layout["fiducials"]):
        c.setFillGray(0)
        x, y = P(fx - fs / 2, fy + fs / 2)
        c.rect(x, y, fs * mm, fs * mm, stroke=0, fill=1)
        c.setFillGray(1)
        cx, cy = P(fx, fy)
        c.circle(cx, cy, 0.5 * mm, stroke=0, fill=1)
        c.setFillGray(0)
        c.setFont("Helvetica-Bold", 7)
        dx = 4 if fx < W / 2 else -6
        dy = 4.5 if fy < H / 2 else -2.5
        tx, ty = P(fx + dx, fy + dy)
        c.drawString(tx, ty, str(i + 1))

    # Color patches
    for p in layout["patches"]:
        r, g, b = (v / 255 for v in p["srgb"])
        c.setFillColorRGB(r, g, b)
        x, y = P(p["x"], p["y"] + p["h"])
        c.rect(x, y, p["w"] * mm, p["h"] * mm, stroke=0, fill=1)

    # Strip slot
    s = layout["stripSlot"]
    c.setStrokeGray(0.35)
    c.setLineWidth(0.6)
    c.setDash(3, 2)
    x, y = P(s["x"], s["y"] + s["h"])
    c.rect(x, y, s["w"] * mm, s["h"] * mm, stroke=1, fill=0)
    c.setDash()
    c.setFillGray(0.55)
    c.setFont("Helvetica", 5.5)
    tx, ty = P(s["x"] + 1.5, s["y"] + s["h"] - 1.5)
    c.drawString(tx, ty, "lay strip here, pads up")

    # Text
    c.setFillGray(0.2)
    c.setFont("Helvetica-Bold", 7)
    tx, ty = P(W / 2, 7)
    c.drawCentredString(tx, ty, f"NITRATE STRIP REFERENCE CARD  v{layout['version']}")
    c.setFont("Helvetica", 5.5)
    tx, ty = P(W / 2, 63)
    c.drawCentredString(tx, ty, "Print at 100%. Keep dry, flat and out of sunlight.")
    tx, ty = P(W / 2, 66)
    c.drawCentredString(tx, ty, "Use the same printed card for calibration and readings.")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--a4", action="store_true")
    args = ap.parse_args()
    page = A4 if args.a4 else letter
    out = ROOT / "assets/reference_card.pdf"
    c = canvas.Canvas(str(out), pagesize=page)
    c.setTitle("Nitrate strip reference card")
    pw, ph = page
    W, H = layout["width"] * mm, layout["height"] * mm
    gx, gy = 8 * mm, 10 * mm
    left = (pw - (2 * W + gx)) / 2
    top = ph - 22 * mm

    c.setFont("Helvetica-Bold", 12)
    c.drawString(left, ph - 14 * mm, "Nitrate strip reference cards (cut out one)")
    c.setFont("Helvetica", 8)
    c.drawString(left, ph - 18.5 * mm,
                 "Print at 100% / Actual size, with no fit-to-page or scaling, on matte white paper.")

    for row in range(3):
        for col in range(2):
            draw_card(c, left + col * (W + gx), top - row * (H + gy))

    # 50 mm ruler to verify print scale
    ry = 14 * mm
    c.setStrokeGray(0)
    c.setLineWidth(0.6)
    c.line(left, ry, left + 50 * mm, ry)
    for i in range(0, 51, 5):
        tick = 3 * mm if i % 10 == 0 else 1.5 * mm
        c.line(left + i * mm, ry, left + i * mm, ry + tick)
    c.setFont("Helvetica", 7)
    c.drawString(left + 52 * mm, ry, "<- this line should measure exactly 50 mm")
    c.showPage()
    c.save()
    (ROOT / "docs").mkdir(exist_ok=True)
    shutil.copy(out, ROOT / "docs/reference_card.pdf")
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
