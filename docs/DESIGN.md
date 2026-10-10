# 03 · Liquid Glass design system

Target: Apple's iOS 26 Liquid Glass, as in the reference screenshots
(`Echo-Music/hyde/*.jpeg`): floating glass chrome, refraction at the edges,
a rainbow fringe where bright content passes under the rim, springy motion.
**Cupertino only** — `package:flutter/material.dart` and Material `Icons` are banned
(`tool/check_no_material.sh`, `uses-material-design: false`).

## 1 · How the glass is rendered

All glass is drawn by **[liquid_glass_easy](https://pub.dev/packages/liquid_glass_easy) 4.3.4**
(MIT). Hyde wraps it so the whole app is tuned in one place:

| Hyde widget | Package piece |
|---|---|
| `LiquidGlass` / `LiquidGlass.capsule` (`design/glass/liquid_glass.dart`) | `LiquidGlassLens` — live-backdrop refraction on Impeller; `flex: true` adds `LiquidGlassTouch(flex: LiquidGlassFlex())` (press swell, drag stretch, spring-back) |
| bottom tab bar (`features/shell/app_shell.dart`) | `LiquidGlassTabBar.withImpeller` — the selection pill lifts into glass, stretches on launch, squashes on landing |
| `GlassSwitch`, `GlassSlider` | `LiquidGlassSwitch`, `LiquidGlassSlider` (slider gets Hyde's division snapping + haptics) |
| `GlassSegmentedControl` | Hyde's own: a flex lens pill on a spring (the package's segmented controls are not exported yet) |
| menus, sheets, dialogs, toasts, mini player, buttons | `LiquidGlass` (→ `LiquidGlassLens`) |

`GlassStyle` → `LiquidGlassStyle` mapping (`LiquidGlass.toLensStyle`): blur → `appearance.blur`,
tint → `appearance.color`, saturation, refraction px → `refraction.distortion` (÷160),
bezel → `distortionWidth`, magnify → `magnification`, dispersion → `chromaticAberration` (×0.008),
light → `shape.lightIntensity/lightDirection`, continuous-corner shape.

Shaders are compiled before the first frame (`LiquidGlassShaders.ensureLoaded()` in `main`).
Settings ▸ Appearance ▸ Glass quality **Frosted** switches the package to lite glass
(`LiquidGlassEngine.liteGlassOnImpeller`); **Renderer** shows what the phone runs.

### Rules
* Never put glass inside `Opacity` / `ShaderMask` — pass `opacity:` to `LiquidGlass`.
* Glass floats above content (chrome, menus, sheets); in-content surfaces stay solid.
* Don't put lenses inside scrolling lists (package guidance) — the segmented control and
  player toggles are fixed controls.

## 2 · Presets (`GlassStyle`)
Rule of thumb: **low frost, strong lens**. Heavy blur is what makes glass read
as "just blur"; the liquid look comes from magnification, rim bending, the
spectral fringe and the specular rim.

| Preset | Used for | blur | bezel | refraction | magnify | dispersion | tint |
|---|---|---|---|---|---|---|---|
| `regular` | generic | 6 | 22 | 24 | 1.05 | 0.50 | none |
| `bar` | tab bar, mini player, toolbar discs | 4 | 20 | 26 | 1.06 | 0.55 | #101012 @22% |
| `clear` | tab droplet, switch/slider knobs, pane toggles, Find orb | 0.6 | 26 | 30 | 1.14 | 0.75 | none |
| `menu` | popover menus, tempo sheet (legibility) | 22 | 22 | 18 | 1.00 | 0.45 | #3A3A3E @30% |

`magnify` (shader uniform 20) pulls samples toward the centre: content under
the glass is visibly enlarged like a lens, which is the strongest "liquid" cue
while things scroll underneath. Settings ▸ Appearance ▸ **Renderer** shows
whether the device runs the shader or the frosted fallback.

Pressed controls lerp from their preset toward `clear` (`GlassStyle.lerp`) —
the control visibly turns into a lens under the finger.

## 3 · Motion
All interactive motion is spring-based and retargetable (`core/motion/hyde_motion.dart`),
specified as SwiftUI (response, damping):

| Token | (response, damping) | Used for |
|---|---|---|
| `smooth` | 0.50, 1.00 | page-level changes, player pane switch, lyrics scroll |
| `snappy` | 0.38, 0.86 | tab selection, compact chrome morph |
| `bouncy` | 0.42, 0.68 | press release, menu pop-in, mini player swipe return |
| `press` | 0.18, 1.00 | touch-down |

Signature interactions:
* **Glass press** (`GlassPressable`) — swell to ×1.08–1.12, lean toward the finger,
  squash/stretch along the drag, bouncy release, selection haptic.
* **Tab bar** — switching tabs *lifts* the pill into a clear glass droplet
  (press spring), glides it with the smooth spring while it stretches along the
  travel and squashes across it (≈ constant area), magnifying the icons it passes
  over, then *drops* back into a soft pill with a bouncy landing. Dragging keeps
  the droplet under the finger with a haptic tick per tab. The whole bar swells
  2.5% while touched.
* **Switch** (`GlassSwitch`) — white knob at rest; on touch it swells into a
  clear lens floating above the track (refracting the green/grey track), follows
  the finger, decides on release, bouncy settle. Tap toggles.
* **Slider** (`GlassSlider`) — same lens knob; snaps to divisions with a haptic tick.
* **Compact chrome** — scrolling content down morphs [tab bar + mini player]
  into [active-tab disc] [mini player] [search disc]; scrolling up reverses.
* **Menu** — grows from the anchor (••• button) with a jelly overshoot
  (height lags width), content fades in after 35%.
* **Sliders** (`ElasticSlider`) — thicken on touch, relative drag, rubber-band
  past the ends (√-damped), end icons get nudged, haptic at the limits.
* **Player** — artwork shrinks to 82% when paused; artwork morphs between big
  and header thumbnail for lyrics/queue panes; drag-down to dismiss with
  rounded-corner card.
* **Lyrics** — active line full white, others 32–38% and blurred by distance
  (σ ≈ 1.1 × lines away, max 4); spring auto-scroll keeps the active line at 22%;
  manual scroll pauses for 3 s and un-blurs; breathing dots for interludes.

## 4 · Tokens
* Accent `#FA2D48` (back chevrons, active tab, links, "Clear All").
* Background black, grouped fill `#1C1C1E`, separators `#38383A`.
* Settings icon tints match the reference (teal, purple, blue, yellow, cyan,
  indigo, green, orange, slate, mint, tan, pink).
* Type: Inter variable (SF Pro is licensed for Apple platforms only), iOS metrics:
  large title 34–44/800, title 22–28/700, body 17/400, footnote 13.
* Corners: `RoundedSuperellipseBorder` / `ClipRSuperellipse` (continuous corners),
  groups 26, artwork 10, menu 34.
* Icons: `CupertinoIcons` only.

## 5 · Screen specs (from the references)
| Screen | Key specs |
|---|---|
| Settings | 44pt large title, search capsule, account card with initial in accent, inset groups (26 radius) with 27pt tinted line icons, chevrons, separators inset under the title. Collapsed: `‹ Settings` small title. |
| Library | Toolbar: search disc + "Downloads" glass pill (accent). Rows: accent icon, 23pt title, chevron. "Recently Added" 2-col grid. |
| Playlists | Search capsule, "N playlists" + "+ Create playlist" (accent), 2-col artwork grid. |
| Search | Field with source dropdown + paste button, "Recent" / "Clear All", rows with type-coloured subtitle and ✕. |
| Now Playing | Grabber, artwork with shadow, title 25pt + artist, ☆ and •••, scrubber with format label centred, ◀◀ ❚❚ ▶▶, volume with speaker icons, bottom: lyrics / devices / queue (active pane on glass disc). |
| Player menu | Glass popover: Favorite + Share quick actions, then grouped rows with subtitles (Go to Album/Artist), separators. |

## 6 · Performance budget
* Each glass = 2 backdrop passes (+ up to 6 texture taps only inside the rim band).
* Budget: ≤ 6 glass shapes on screen at once; ≤ 2 large (> 25% screen) ones.
* Profile on a mid-range device: `flutter run --profile`, check raster time
  < 8 ms with the tab bar + mini player over a scrolling grid.
* Settings ▸ Appearance ▸ Glass quality: **Full** (refraction) / **Frosted**.
  Phase 3: auto-switch to Frosted when raster time stays > 14 ms for 2 s.
