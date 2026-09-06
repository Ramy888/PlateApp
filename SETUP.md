# PlatePatch — release setup

Everything the code cannot do for itself, in the order it has to happen.
Steps that block other steps are marked **blocking**.

---

## 0. The deadline maths (read first)

Your Play Console account is a **personal** account, so Google's testing
requirement applies: **12 testers opted in continuously for 14 days** before you
can even apply for production access, and that application then takes
**3–7 days** to review.

| Step | Earliest date |
|---|---|
| Closed-test build live, 12 testers opted in | **6–7 Sep** |
| 14 continuous days complete | 21 Sep |
| Production access review (3–7 days) | 24–28 Sep |
| Production release review (1–3 days) | 27 Sep – 1 Oct |
| **Shipaton deadline** | **30 Sep, 23:45 PDT** |

Play alone lands somewhere between "two days early" and "one day late", with no
SLA anywhere in the chain. So:

> **Enrol in the Apple Developer Program today.** iOS has no tester gate and
> reviews in roughly 24–48 hours. Shipaton accepts App Store, Google Play *or*
> Samsung Galaxy Store, and this is the same Flutter codebase either way. iOS is
> the reliable path to "publicly live"; Play is the parallel one.

Two things only you can do, today:

1. **Apple Developer Program** — $99/yr, individual enrolment can take 24–48h.
2. **Line up 12 Play testers** — 12 real Gmail accounts in a Google Group, so
   the 14-day clock starts the moment the first closed-test build is live.

The clock counts **testers opted in**, not build age. Ship a working build now
and keep updating the closed track daily — updates do **not** reset the 14 days.

---

## 1. Play Console — get an AAB uploaded (blocking)

Products cannot be created until Play has seen a build containing the billing
library, so this genuinely comes first.

1. Create the app in Play Console. Package name must be exactly
   **`com.platepatch.app`** — it can never be changed afterwards.
2. Confirm phone verification and the **merchant/payments profile** are fully
   cleared. Subscriptions cannot be created without a payments profile.
3. Build and upload to **Internal testing**:

   ```bash
   flutter build appbundle --release
   # build/app/outputs/bundle/release/app-release.aab
   ```

4. Accept Play App Signing when prompted (recommended — Google holds the app
   signing key, your upload key stays local).

### Your upload key — back this up now

`android/key.properties` and `android/platepatch-upload.jks` are **gitignored on
purpose**. If you lose them you cannot ship an update to this app, ever.

```
keystore: android/platepatch-upload.jks
alias:    upload
password: (in android/key.properties — copy it into your password manager)
SHA-1:    A1:BE:72:E7:48:11:CA:75:FE:A8:04:09:60:5A:11:92:55:E7:F8:EB
SHA-256:  FC:1E:17:12:00:57:D2:C6:D2:8A:DF:82:BB:F0:04:2F:6A:60:0B:0D:D6:D5:47:71:7E:AC:D7:BE:7D:DB:F5:1D
```

---

## 2. Play Console — subscriptions

Create two subscriptions under **Monetise → Subscriptions**:

| Product ID | Base plan ID | Billing period | Price |
|---|---|---|---|
| `platepatch_pro_monthly` | `monthly` | 1 month, auto-renewing | ~$1.99 |
| `platepatch_pro_yearly` | `yearly` | 1 year, auto-renewing | ~$11.99 |

Then, on the **yearly** base plan, add an **Offer** of type *Free trial*, phase
duration **7 days**. The trial lives here, not in the app — the paywall reads it
back from the store and renders whatever Play reports. Activate both base plans
and the offer.

Shipaton requires a working free trial, so verify the offer shows as **Active**.

---

## 3. Play Console — service account for RevenueCat

RevenueCat needs Play API access to validate purchases.

1. Google Cloud Console → the project linked to Play → **Create service
   account** → grant it the *Pub/Sub Editor* role → create a **JSON key**.
2. Play Console → **Users and permissions** → invite the service account email →
   grant *View app information*, *View financial data*, and *Manage orders and
   subscriptions*.
3. Upload the JSON to RevenueCat.

> Google says credentials can take **up to 36 hours** to propagate. Start this
> today even if nothing else is ready.

---

## 4. RevenueCat dashboard

1. New project → add a **Google Play** app → package `com.platepatch.app` →
   upload the service account JSON from step 3.
2. **Entitlements** → create one with identifier exactly **`platepatch_pro`**.
   The app checks this string; a typo means purchases succeed and unlock nothing.
3. **Products** → import `platepatch_pro_monthly` and `platepatch_pro_yearly`.
4. **Offerings** → create an offering with identifier **`default`** →
   add a package of type **Monthly** → `platepatch_pro_monthly`,
   and a package of type **Annual** → `platepatch_pro_yearly`.
   Make it the **current** offering.
5. Attach both products to the `platepatch_pro` entitlement.
6. Copy the **public Android SDK key** (starts `goog_`).

### Sanity check

| Where | Must be exactly |
|---|---|
| Entitlement identifier | `platepatch_pro` |
| Offering identifier | `default` |
| Package types | Monthly + Annual |

---

## 5. Build with the key

The key is never committed; it is passed at build time.

```bash
flutter build appbundle --release \
  --dart-define=REVENUECAT_ANDROID_KEY=goog_YOUR_KEY_HERE
```

**Bump the version before every upload** — Play rejects a repeated versionCode.
In `pubspec.yaml`, `version: 1.0.0+1` → `1.0.0+2` (the number after `+` is the
versionCode).

Without the key the app still builds and runs perfectly; the paywall simply
reports that Pro is unavailable and the free experience is untouched. That is
deliberate, so a missing key can never brick a release.

For iOS later, the equivalent is `--dart-define=REVENUECAT_IOS_KEY=appl_...`.

---

## 6. Closed testing (the 14-day clock)

1. Create a **Closed testing** track, upload the keyed AAB.
2. Create a Google Group with your 12 testers and attach it as the tester list.
3. Send everyone the opt-in link and confirm **all 12 actually opt in** — an
   invited tester who never opts in does not count.
4. Ask them to open the app more than once over the fortnight. Google looks at
   whether testers genuinely used it when reviewing production access.

A closed-track release goes through review, so the listing must be complete
first — see step 7.

### License testers (so you can test purchases for free)

Play Console → **Setup → License testing** → add your own Gmail account. Test
purchases then complete without being charged, and the 7-day trial compresses so
renewals can be observed quickly.

---

## 7. Store listing requirements

All of these gate a closed-track review:

- [ ] Short and full description — copy in `STORE_LISTING.md`
- [ ] App icon 512×512 — from `assets/icon/icon.png`
- [ ] Feature graphic 1024×500 — `assets/icon/feature_graphic.png`
- [ ] At least 2 phone screenshots — regenerate with `tool/capture_screens.sh`
- [ ] **Privacy policy URL** — publish `docs/` to GitHub Pages (below)
- [ ] Content rating questionnaire
- [ ] Target audience and content
- [ ] **Data safety form** — see below
- [ ] **Health apps declaration** — nutrition apps are usually asked; answer
      that PlatePatch gives general food suggestions, is not a medical device,
      and does not handle health records

### Publishing the privacy policy

```bash
# in a GitHub repo for this project
git push origin main
# GitHub → Settings → Pages → Source: main branch, /docs folder
```

That gives `https://<your-username>.github.io/platepatch/privacy.html`. Put that
URL in the Play listing. The app itself shows the same text on an in-app screen,
so a broken link can never strand a user.

### Data safety form

PlatePatch collects nothing itself, but **RevenueCat does** and the form must
reflect that:

| Data type | Collected | Shared | Purpose |
|---|---|---|---|
| Purchase history | Yes | Yes (RevenueCat) | App functionality |
| Device or other IDs | Yes | Yes (RevenueCat) | App functionality |
| Everything else | No | No | — |

Data is encrypted in transit. There is no account, so there is no deletion
request mechanism — uninstalling removes all local data. Declare **no** data
deletion URL and note that no personal data is collected.

---

## 8. Verifying the purchase actually works

Before submitting, on a real device with a license-tester account:

1. Open the paywall → both plans show with **real prices from Play**, and the
   yearly card shows the trial badge.
2. Buy the yearly plan → locked foods unlock, saved patches go unlimited.
3. Force-quit and reopen → still Pro (entitlement is read on launch).
4. Uninstall, reinstall, tap **Restore purchases** → Pro comes back.
5. Turn off wifi and open the paywall → "Pro is not available right now", no
   crash, and the free app still works.

Step 4 is a hard Shipaton requirement and the most commonly missed one.

---

## 9. Submission checklist (Shipaton)

- [ ] First public release falls inside 1 Aug – 30 Sep 2026
- [ ] RevenueCat SDK powering a real in-app purchase in production
- [ ] Live store URL, downloadable in the United States
- [ ] English store description
- [ ] Public demo video under two minutes
- [ ] 1024×1024 icon
- [ ] At least one 1179×2556 screenshot with no device frame
- [ ] Free trial working
- [ ] Restore Purchases button (built, on the paywall footer)
- [ ] English testing instructions
- [ ] Build-in-public links

One rule worth repeating: **do not use the influencer's name, photo, voice,
branding or logo** anywhere in the app, the listing, or the marketing. The
official rules prohibit it without written permission.
