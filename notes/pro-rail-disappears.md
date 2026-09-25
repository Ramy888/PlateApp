# The Pro rail vanishes at the moment of purchase

Found 25 Sep 2026 on a real device, signed in as the account holding Pro.

## What someone sees

Signed out, the meal picker shows the eight ordinary rails plus one more:
**Egyptian, MENA & world**, carrying a Pro tag. Sign in with a Pro account and
that rail is gone.

Nothing is actually lost. Confirmed on the device: **Made dishes** for a Pro
user reads *Pizza, Burger, Sandwich, Fuul medames* — the MENA food is there,
unlocked, in an ordinary rail.

## Why it happens

A food carries two fields (`lib/domain/models.dart`):

- `group` — one of the eight cuisine-agnostic rails in `FoodGroup.all`
  (grains, protein, dairy, veg, fruit, dishes, sweets, drinks)
- `collection` — `common` is free, anything else (`mena`, `world`) is Pro

**Egyptian, MENA & world is not a group.** It is `FoodGroup.locked`
(`models.dart:362`), a synthetic rail that `_rails()` builds *only* when
`isPro` is false (`lib/ui/food_picker_screen.dart:131-140`). The comment there
says what it is for:

> Every locked collection collapses into one rail. Showing them is what sells
> Pro; showing them scattered through eight rails just reads as eight things
> that do not work.

That reasoning holds for the free user. It was never extended to the paid one.
The moment `isPro` flips, the teaser rail stops being built and its 19 foods
scatter into the eight ordinary rails by `group`:

| Group | Pro foods |
|---|---|
| dishes | 13 |
| veg | 3 |
| grains | 1 |
| fruit | 1 |
| sweets | 1 |

11 are `mena`, 8 are `world`. Examples: Fuul medames, Taameya or falafel,
Koshari, Shawarma (dishes); Molokhia, Mahshi (veg).

## Why it is worth fixing

The named thing someone paid for disappears at the instant they pay for it, and
the 19 foods land unlabelled across five rails with nothing marking them as the
unlock. The purchase reads as a downgrade. The code does exactly what it was
written to do — this is a product problem, not a defect.

It also undercuts the pitch. "Egyptian, MENA and world foods" is a line on the
paywall (`paywall_screen.dart:56`); a subscriber never sees that phrase again.

## Two ways out

1. **Keep the rail for Pro too.** Build `FoodGroup.locked` regardless of
   `isPro`, without the lock flag, in addition to the merged items. Smallest
   change, and it answers "where did my thing go" directly. Costs one
   duplicated appearance per Pro food, which is the point rather than a bug.
2. **Mark the unlocked items.** A small globe badge on any food whose
   `collection` is not `common`, shown inside the ordinary rails, so the unlock
   is visible where it landed.

Prefer 1. Both need a build, so neither is a Shipaton-week change — a Play
review is 1-3 days and the submission is already in.
