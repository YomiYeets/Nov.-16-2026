# Nitrate Strip Reader

A Flutter app (iOS + Android) that reads Hach-style nitrate test strips
(0–50 mg/L NO3-N) from a photo. It corrects the photo's colors with a printed
reference card and converts the pad color to a concentration with a
calibration curve you build from known standards.

**Units.** Results are reported as **nitrate-nitrogen (mg/L NO3-N)**, the unit
used on most Hach strip charts and in the US EPA drinking-water limit
(10 mg/L NO3-N). The nitrate-ion equivalent (mg/L NO3-, ×4.427) is shown
alongside. Make your calibration standards up in NO3-N.

## How it works

1. **Home**: pick *Nitrate*, set the development time (default 60 s, `+`/`−`),
   dip a strip, tap **Start**.
2. **Timer**: counts down. Lay the strip in the card's dashed slot. When time is
   up it beeps and opens the camera.
3. **Camera**: line the card up with the on-screen outline and take the photo.
   Flash is off by default because it causes glare.
4. **Select**: pinch-zoom and tap the centers of corner marks **1 → 4**, then the
   **nitrate pad**. Green boxes show where each patch will be sampled, so you
   can check alignment. Adjust the pad circle with the slider.
5. **Analyze**: color correction → CIELAB → calibration curve → result in mg/L
   with a 95% range and quality warnings. Add a site name (it autocompletes
   from earlier sites); GPS is recorded automatically. Save to the log.

**Calibration** (*Calibration curves*): create one curve per strip lot, then
*Add standard* → pick 0/5/10/20/50 mg/L (or type another value) → the same
timer/camera/select flow → *Add to curve*. Pick the active curve with the radio
button.

**Log**: every reading with date, time, GPS, site, result, range, Lab color,
quality metrics and photo. Export as CSV, or as a ZIP of CSV plus photos,
through the share sheet.

**Reference card**: `docs/reference_card.pdf` (also shareable from the app).

## Getting good numbers

* Print the card at **100% / Actual size** on matte paper and check the 50 mm
  ruler. Use the **same printed card** for calibration and field readings.
* Use **2–3 separate strips per standard**. Repeats are what give the app a
  real confidence range instead of a provisional default.
* Keep the timing identical: dip for the same time, and photograph as soon as
  the timer ends. The log records how late each photo was taken.
* Use even, indirect light (open shade, overcast sky). Avoid direct sun,
  mixed light, and shadows across the card.
* Recalibrate for each new lot of strips and when strips near expiry.
* Watch the warnings: a high *card fit error* means a bad photo; a high
  *distance from calibration curve* means the color doesn't behave like your
  standards.

The precision limit is the strip chemistry, not the camera. Use the replicate
scatter shown on the curve screen (ΔE, and ΔE per mg/L for each range) to say
how precise the method really is.

## Building

Requires Flutter 3.50+ (`flutter --version`).

```bash
flutter pub get
flutter test             # unit tests for the color math and the full pipeline
flutter run              # with a phone connected
```

iOS builds need a Mac with Xcode (open `ios/Runner.xcworkspace` once to set
your signing team). Camera, location and photo-library permission prompts are
already configured.

To change the card, edit `assets/card_layout.json` and run
`python3 tools/make_card.py` (needs `pip install reportlab`). The app and the
PDF read the same file. Add `--a4` for A4 paper.

## Code map

| Path | What it does |
| --- | --- |
| `lib/color/color_space.dart` | sRGB ↔ linear RGB ↔ XYZ ↔ CIELAB, ΔE |
| `lib/color/color_correction.dart` | Gray-ramp tone curves + 3×4 color matrix fitted to the card |
| `lib/color/calibration_curve.dart` | Lab → concentration by projecting onto the calibration path; confidence range |
| `lib/color/homography.dart` | Maps card millimetres to photo pixels from the 4 tapped marks |
| `lib/color/sampling.dart` | Trimmed-mean color of the pad and patches |
| `lib/analysis/analyzer.dart` | The full per-photo pipeline (pure Dart, testable) |
| `lib/screens/` | UI: home, timer, camera, select/analyze, result, calibration, log, card |
| `lib/data/` | SQLite storage, models, CSV/ZIP export |
| `docs/COLOR_MATH.md` | The color math explained for writing about it |

## Roadmap

* Automatic card detection: find the four corner marks in the photo and feed
  them to the same `analyzePhoto()` function.
* Automatic pad detection from the strip slot.
* Plot of the calibration path (L\*, a\* vs concentration).
* Optional measured Lab values for the printed card (already supported in
  `card_layout.json` via a `"lab"` field), so curves can be shared between cards.
