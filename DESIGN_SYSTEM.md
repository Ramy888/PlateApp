# PlatePatch design system

The visual reference — rendered swatches, live components, and a paste-ready
prompt for every screen — is published here:

**https://claude.ai/code/artifact/57fe0906-0654-4305-94c6-9955588591f1**

This file is the text mirror for tooling. **If this and the code disagree, the
code wins** — `lib/ui/theme.dart` and `lib/ui/widgets/common.dart` are the
source of truth.

---

## Principles

1. **Only ever add.** Nothing implies the user's food is wrong. No red, no
   warning iconography, no "too much" language.
2. **No numbers people can fail at.** No calories, grams, macros or weights,
   anywhere. Portions are objects: "half a cup", "what fits in a cupped palm".
   Enforced by a test over the shipped catalogue and copy.
3. **One decision per screen.** One question, one primary action. Two primary
   buttons means it is two screens.
4. **Warm, not clinical.** A friend passing you something across the table, not
   a health dashboard.

## Colour

The app is light-only by design; these are fixed product values, not themed.

| Token | Hex | Used for |
|---|---|---|
| `cream` | `#FBF7F0` | Every scaffold and app bar — the ground |
| `card` | `#FFFFFF` | Anything lifted off the ground |
| `ink` | `#1F2420` | Headings and body (green-biased near-black) |
| `inkSoft` | `#5C665E` | Secondary text, captions, inactive icons |
| `line` | `#E7E0D5` | Every border and divider |
| `green` | `#2E6B4F` | Primary buttons, selected state, links |
| `greenSoft` | `#DCEBE2` | Selected fills, plant-based pill, success |
| `amber` | `#E8A33D` | Pro borders and accents — never a button fill |
| `amberSoft` | `#FBEBD2` | Pro cards, "Fastest" pill |
| `clay` | `#C96F4A` | Text on amber/clay grounds |
| `claySoft` | `#F8E2DA` | "Cheapest" pill |

**There is no error red**, deliberately. Failures are information on a standard
card. The one exception is `clay` on a future destructive action.

## Type

System sans (Roboto / SF). Personality lives in colour, spacing and copy.

| Role | Size / line / weight / tracking | Used for |
|---|---|---|
| `displaySmall` | 32 / 1.15 / 700 / −0.6 | Onboarding and check headlines |
| `headlineMedium` | 26 / 1.2 / 700 / −0.4 | Screen titles, result headline |
| `titleLarge` | 19 / 1.3 / 600 | Addition name on a patch card |
| `titleMedium` | 16 / 1.35 / 600 | Row titles, list headings |
| `bodyLarge` | 16 / 1.45 / 400 | Portion guidance, policy text |
| `bodyMedium` | 14.5 / 1.45 / 400 (inkSoft) | Subtitles, reasons, captions |
| `labelLarge` | 15 / 600 / +0.1 | Buttons |

## Space and shape

`xs 4 · sm 8 · md 16 · lg 24 · xl 32 · xxl 48`. Anything off this scale is a bug.

| | |
|---|---|
| Card radius | `20` (`kRadius`) |
| Button / tile radius | `14` (`kRadiusSmall`) |
| Pill radius | `999` |
| Button height | `54`, full width, one filled button per screen |
| Card border | `1.5px` |
| Screen padding | `24` horizontal |
| Elevation | `0` — borders separate things, not shadows |

## Components

`PlateCard` · `ChoiceRow` · `Pill` · `FoodTile` · `SlotChip` · filled/outlined
buttons · `PatchCard` · `EmptyState`. All in `lib/ui/widgets/common.dart` except
`PatchCard` (private to `result_screen.dart`) and the tiles (private to
`meal_screen.dart`).

`ChoiceRow` takes `showIndicator: false` where a tap acts immediately — a
chevron replaces the circle, so it never implies a confirm step that isn't there.

## Screens

Thirteen screens and one sheet. Screens 5–7 are the AI scan flow.

| # | Screen | File | Status |
|---|---|---|---|
| 1 | Welcome | `onboarding_screen.dart` | Built |
| 2 | Goal | `onboarding_screen.dart` | Built |
| 3 | Preferences | `onboarding_screen.dart` | Built |
| 4 | Meal picker | `meal_screen.dart` | Built |
| 5 | Scan camera | `scan_camera_screen.dart` | Built |
| 6 | Confirm what it saw | `scan_confirm_screen.dart` | Built |
| 7 | Preview my patch | `preview_screen.dart` | Built |
| 8 | Your PlatePatch | `result_screen.dart` | Built |
| 9 | After-meal check | `check_screen.dart` | Built |
| 10 | Saved patches | `saved_screen.dart` | Built |
| 11 | Paywall | `paywall_screen.dart` | Built |
| 12 | Privacy & terms | `legal_screen.dart` | Built |
| 13 | Settings | `settings_screen.dart` | Built |
| S | Report this result | `widgets/report_sheet.dart` | Built |

## Deliberately not built

**Camera scanning and Settings were once on this list and are now built.** What
genuinely stayed out:

| Dropped | Why |
|---|---|
| Sign in, register, forgot password, account | No accounts. Scanning uses an anonymous device token that identifies a quota, not a person. |
| Streaks, badges, daily goals | A game layer turns a nudge into an obligation — the failure mode the product exists to avoid. |
| Barcodes, recipes, meal plans | Each answers a different question than "what could I add to this?" |
| An open-ended chatbot | The AI has two jobs: read a photo, draw one. Both are fixed-prompt calls. A chat box would be a fourth product and an unbounded safety surface. |

## Store assets

Full specs and the screenshot running order are in the artifact. Summary:

| Asset | Spec | Source | State |
|---|---|---|---|
| App icon | 512×512 PNG, no alpha, no rounded corners | `assets/icon/icon.png` | Ready |
| Feature graphic | 1024×500, no alpha | `assets/icon/feature_graphic.png` | Ready |
| Phone screenshots | 2–8, each edge 320–3840px | `./tool/capture_screens.sh` | **Needs re-run — the scan flow is new** |
| Shipaton screenshot | ≥1 at 1179×2556, no device frame | iPhone 15 Pro simulator | Not captured |
| Promo video | Public YouTube, <2 min | — | Not made |

```bash
dart run tool/generate_icon.dart   # icon, adaptive layers, feature graphic
flutter build apk --release
./tool/capture_screens.sh          # screenshots from a running emulator
```

## Voice

| Never | Instead |
|---|---|
| calories, kcal, macros, grams, weigh | "half a cup", "what fits in a cupped palm" |
| "You should…", "Avoid…", "Cut down on…" | "Add…", "Swap in…", "Stir through…" |
| "bad", "unhealthy", "cheat", "treat" | Name the food. No adjective. |
| "Oops! Something went wrong 😬" | "The store could not be reached. Check your connection and try again." |
| Streaks, badges, daily goals | Nothing. There is no game layer. |
| "Powered by AI", "Smart", "Intelligent" | Say what it did: "PlatePatch thinks it sees this." |
| Presenting a recognition as fact | "thinks it sees", "Not very sure about this one." |
| Hiding that a preview is generated | "AI visual preview — appearance and serving size are illustrative." Always visible, never dismissible. |
| Letting an AI failure be a dead end | Every error ends with "…or build the meal by hand." |

Recurring shapes: suggestions lead with an imperative verb; portions name an
everyday object then reassure; reasons state facts (`Covers protein and fibre.`);
headlines say *looks* light, not *is* light — the app is guessing and should
sound like it.
