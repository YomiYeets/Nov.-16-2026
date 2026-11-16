# The color math, step by step

This explains how a photo of a test strip becomes a nitrate concentration.
The same explanations appear as comments in the source files named below.

## 1. From pixels to light: linearizing sRGB
*`lib/color/color_space.dart`*

A JPEG stores *encoded* sRGB values (0–255). The encoding is non-linear, so
code 128 is about 22% of the light of code 255, not 50%. Light adds linearly,
so averaging and color correction must work on linear values. We first undo
the sRGB curve:

```
c = v/255
linear = c / 12.92                    if c ≤ 0.04045
linear = ((c + 0.055) / 1.055)^2.4    otherwise
```

## 2. Averaging the pad
*`lib/color/sampling.dart`*

All pixels inside the pad circle are linearized. They are sorted by luminance,
the brightest and darkest 10% are dropped (glints, edges, specks), and the
rest are averaged. The standard error of that mean (SD/√n) is kept as the
photo's own measurement noise. Clipped pixels (0 or 255) are counted, and the
app warns about glare.

## 3. Locating the card: a homography
*`lib/color/homography.dart`*

The four tapped corner marks and their known positions on the card (in mm)
determine the 3×3 perspective transform H (8 unknowns, 2 equations per
point). H tells us where every patch of the known layout falls in the photo,
even when the phone is tilted. Each patch is sampled over the inner 60% of
its area.

## 4. Color correction against the reference card
*`lib/color/color_correction.dart`*

The card has 6 neutral grays, 6 pinks that span the pad's color range, and 6
saturated anchors. Whatever the light and camera did to the patches, they
also did to the pad. Two stages undo it, both in linear RGB:

1. **Per-channel tone curves from the grays.** For each of R, G and B, plot
   measured value against known value for the six grays and join the points
   with a monotonic piecewise-linear curve through (0,0). This fixes
   exposure, white balance and most of the phone's tone curve.
2. **A 3×4 affine color matrix from all patches.**
   `[R' G' B']ᵀ = M · [R G B 1]ᵀ`, fitted by weighted least squares
   (pinks ×3, since they resemble the pad). The fourth column absorbs flare.
   A light ridge penalty pulls M toward the identity so a poor photo can't
   produce a wild matrix.

The RMS ΔE between corrected patches and their known values is the **card fit
error**, a per-photo quality score (under 2 is good, over 3 triggers a
warning).

In the synthetic test (`test/color_math_test.dart`), a strong simulated warm
cast with channel cross-talk and a non-linear response put a pad-like color
19.8 ΔE off. After correction it was 0.6 ΔE off.

**Why nominal card colors are good enough:** if the printed patches differ from
their nominal values, every photo is mapped into the same slightly shifted
color space. Calibration is done in that same space, so the shift cancels.
The rule is to use the same printed card throughout.

## 5. Into CIELAB
*`lib/color/color_space.dart`*

Corrected linear RGB → XYZ (D65 matrix) → CIELAB:

```
L* = 116 f(Y/Yn) − 16
a* = 500 [f(X/Xn) − f(Y/Yn)]
b* = 200 [f(Y/Yn) − f(Z/Zn)]       f(t) = t^(1/3) (linear near 0)
```

CIELAB is roughly perceptually uniform: the Euclidean distance ΔE between two
colors tracks how different they look (ΔE ≈ 1 is just noticeable side by
side). As nitrate rises the pad moves from near-white toward magenta (L*
falls, a* rises).

## 6. From color to concentration: the calibration path
*`lib/color/calibration_curve.dart`*

Each standard (for example 0, 5, 10, 20, 50 mg/L NO3-N) gives a mean Lab
point. Joined in order of concentration they form a polyline, the
**calibration path**. For an unknown:

1. Find the closest point on the path (perpendicular projection onto each
   segment, keep the nearest).
2. Interpolate linearly between the segment's two standards:
   `C = Cᵢ + t·(Cᵢ₊₁ − Cᵢ)`.
3. The perpendicular distance is the **off-curve ΔE**. If it is large, the
   color isn't behaving like the standards did.

Using all three Lab coordinates handles curved color paths and averages noise
across channels.

## 7. The confidence range
*`lib/color/calibration_curve.dart`*

For standards measured more than once (separate strips and photos), each
replicate's deviation from its level mean is projected onto the local path
direction. These are pooled:

```
σ_along² = Σ (dev · tangent)² / Σ (nₗ − 1)
```

So σ captures real strip-to-strip, timing, lighting and correction
variability. Without replicates a default of 2 ΔE is used and the range is
marked *provisional*. The total uncertainty also includes the uncertainty of
the calibration means (σ²/n) and the photo's pixel noise:

```
σ_total² = σ_along² · (1 + 1/n) + σ_pixel²
```

The range is found by moving ±1.96 σ_total along the path (about 95% for
normal errors) and converting both ends to concentration. Where the color
changes fast per mg/L the range is narrow; where the pad saturates (often at
high concentrations) it widens. The app reports the local sensitivity
(ΔE per mg/L) so you can see this directly.

## Why this can do better than the eye

* It reads a continuous position between standards instead of picking the
  nearest printed block.
* Lighting and camera effects are corrected against known colors in the
  same photo.
* Thousands of pixels are averaged.
* Uncertainty is measured from your own replicates, not guessed.

The limit is the strip chemistry itself. Report the measured σ and
sensitivity when you describe the method's precision.
