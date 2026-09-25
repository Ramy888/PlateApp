# The living plate

A drawn plate on the result page that shows the meal you described and the
addition landing on it, rendered on the phone, instantly, with no network call.

Status: SPEC · Branch `main` · Target release 1.4.1 · Written 11 Sep 2026

---

## Why this exists

The Plate has four ways in and a deterministic engine that answers in
milliseconds. Today that answer arrives as a sentence and then, several seconds
later and only if you are signed in and have tries left, a generated photograph.
Between the tap and the picture there is nothing to look at.

A sibling project built voice-first with a live plate that updates while the
user talks. Two independent reviews (the agent that built it, and Fable 5.1)
both concluded The Plate should **not** collapse to voice-first, and both
conceded the same point: a plate that visibly changes as the patch lands is more
persuasive than a sentence. This spec takes that one idea without the
architecture that came with it.

The thing being stolen is the *feedback*, not the *input method*.

## What it is

On the result page, above the patch line, a drawn plate:

1. The foods the user picked appear on it as their catalogue icons.
2. The chosen addition animates onto the plate — sliding in from the edge and
   settling into a free spot.
3. Tapping a different angle card re-runs the animation with the new addition.

It is drawn from the catalogue's own icons and the app's own palette. No
photography, no model call, no network.

## What it is not

- **Not a replacement for the generated image.** The Cloudflare Workers AI
  photograph stays exactly where it is and keeps its "AI picture" label. The
  diagram is what you see *first* and what you see *instead* when there is no
  picture — signed out, out of tries, offline, or still waiting.
- **Not a new input method.** Nothing about how a meal is described changes.
- **Not realtime.** There is no streaming, no partial state. The engine already
  answers instantly; this draws what it answered.
- **Not a nutrition visualisation.** No portions, no proportions, no quantities.
  The copy rule holds: nothing on screen implies a measured amount.

## Where it goes

`lib/ui/result_screen.dart`, in `_Hero`, which today is a 220pt image well
showing one of three states:

| State | Today | After |
|---|---|---|
| Photo arrived | photo | photo (unchanged) |
| Loading | skeleton shimmer | **diagram** |
| Signed out — the default, `_draw()` returns early | flat card, one grey glyph | **diagram** |
| Out of tries (`needsPro`) | same flat card | **diagram** |
| Worker unreachable | same flat card | **diagram** |

Five states, not three. The review caught that the old third branch was one
fallback standing in for four different situations, and that signed-out is the
*default* rather than an edge — a guest never reaches `loading` at all.

So the diagram is never *instead of* the photograph — it is what fills the well
until, or unless, a photograph exists. A free offline user gets a real answer
with a real picture of it. A paying user gets that and then the photoreal one.

## How it is drawn

A `PlateDiagram` widget in `lib/ui/widgets/`, taking `List<FoodItem> foods` and
`Addition? addition`:

- A cream circle on the card ground, with the faint inner ring the app icon
  uses, so it reads as the same plate the brand is built on.
- Foods laid out on a fixed ring of positions — deterministic by index, so the
  same plate always draws the same way, matching the engine's own promise.
- Each food is its catalogue icon in a soft disc, the same `Lead` vocabulary
  used everywhere else.
- The addition enters last, in sage with a pale glyph, matching the patch badge
  it sits above. It slides from the plate edge and settles.

Layout is positions on a circle, not a physics simulation. Five foods are
shown; beyond that the fifth is followed by a `+N` disc, because a crowded
drawing stops being legible and the point is legibility. (An earlier draft said
six in the prose and five in the tests — five is right.)

## Motion

- One entrance, 620ms. Two curves off one controller: `easeOut` drives opacity,
  `easeOutBack` drives movement. They are separate because `easeOutBack`
  overshoots past 1 — that overshoot *is* the settle — and an opacity above 1
  asserts in debug.
- Foods fade in together; the addition animates after them, so the eye reads
  "this is your meal" then "this is the thing being added".
- Re-runs when the selected angle changes.
- **Stops completely under `MediaQuery.disableAnimationsOf`** — everything draws
  in its final position. Same rule as the walkthrough, the meal-card drift and
  the skeleton, and the same reason: reduced motion is an accessibility answer,
  and a looping animation is a `pumpAndSettle` that never returns.

## Constraints this must respect

| Constraint | How |
|---|---|
| Works offline, signed out, free | Pure widget over catalogue data. No network, no account, no quota. |
| Shipaton: RevenueCat purchase must stay legible | Paywall untouched. The diagram is free-tier; the photograph stays paid. |
| Shipaton: demo video under 2 minutes | It makes shot 3 *shorter* — the answer is now visible immediately rather than after a wait. |
| No calories, grams, macros, weighing | Nothing quantitative is drawn. Enforced by the existing copy test. |
| Deterministic engine | Layout is a pure function of `(foods, addition)`. Same plate, same drawing. |

## Test plan

| Test | Asserts |
|---|---|
| `plate_diagram_test.dart` — renders every food given | One icon per food, in order |
| — caps a crowded plate | Six foods → five icons plus a `+1` disc |
| — the addition is distinguishable | Addition disc uses the sage treatment, foods do not |
| — empty plate | No foods → plate draws, no crash |
| — reduced motion is final-state | With `disableAnimations`, every element is at its end position on first frame |
| — determinism | Same input twice → identical positions |
| `app_flow_test.dart` — the free path shows a plate | Signed out, no network: diagram present in `_Hero` |
| `app_flow_test.dart` — photo wins when it exists | With an image, the photo renders and the diagram does not |

## Risks

1. **Scope against the deadline.** It is 11 Sep; 1.4.1 is built but unshipped,
   and the live 1.4.0 cannot sell a subscription. This feature delays that fix.
   *Mitigation: the AAB is already built and verified. If this runs long, ship
   1.4.1 as it stands and take the diagram to 1.4.2.*
2. **A drawn plate that looks worse than nothing.** Icons on a circle can read
   as clip art.
   *Mitigation: one look on a real device before it is committed, and it uses
   only existing components and palette.*
3. **Another looping animation in the test suite.** Three times this session an
   infinite animation hung `pumpAndSettle`.
   *Mitigation: single-shot entrance, no repeat, gated on reduced motion, and a
   test that asserts the final state.*

## Copy this forces
Three lines elsewhere on the page promised a drawing that now already exists:
"See this plate drawn" becomes "See a photo of this plate", and the two footers
below it distinguish the free drawing from the paid photo. Without this the
page offers to draw a plate it has already drawn.

## Definition of done

- `PlateDiagram` renders in `_Hero` for the loading and no-picture states.
- Animation runs once, re-runs on angle change, stops under reduced motion.
- Tests above pass; full suite green; analyzer clean.
- Seen on a device before commit.
- Rebuilt into the 1.4.1 bundle. **The earlier claim that this avoids a second
  Play review was wrong**: any code change means a rebuild, and a review cycle
  runs in parallel with development rather than instead of it. Bundling costs
  review time; it does not save it.
