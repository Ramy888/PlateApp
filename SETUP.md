# The Plate — release setup

Everything the code cannot do for itself, in the order it has to happen.
Steps that block other steps are marked **blocking**.

---

## 0. The deadline maths (read first)

**Your Play Console account predates 13 November 2023, so the 12-testers-for-14-
days requirement does not apply to you.** That removes the single biggest risk
in this project. Play goes straight from internal testing to production.

| Step | Time needed |
|---|---|
| Upload AAB, complete the listing | a few hours |
| Internal testing (as long as you want) | same day |
| Production release review | 1–3 days, occasionally up to 7 |
| **Shipaton deadline** | **30 Sep 2026, 23:45 PDT** |

Submitting production by **~20 Sep** leaves ten days of slack for a rejection and
a resubmission. There is no reason to cut it closer than that.

iOS is now a bonus rather than a hedge — a second store listing and a shot at
more award categories, not the thing standing between you and qualifying. The
release build already compiles (see section 8b); pick it up once Play is live.

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
   account** → create a **JSON key**. No GCP IAM role is needed for purchases;
   the permissions that matter are granted in Play Console, not here.
2. Play Console → **Users and permissions** → invite the service account email →
   grant *View app information*, *View financial data*, and *Manage orders and
   subscriptions*. **This is the step that actually matters** — skip it and
   RevenueCat cannot validate purchases.
3. Upload the JSON to RevenueCat.
4. Optional, later: to receive RevenueCat's real-time developer notifications,
   also give the service account the *Pub/Sub Editor* role in GCP. Purchases
   work without it — do not let it block you today.

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

## 6. Testing the build

Your account is exempt from the closed-testing requirement, so this is only
about catching your own bugs.

1. Upload the keyed AAB to **Internal testing** and add yourself as a tester.
2. Walk the flow on a real phone, including a purchase (see section 8).
3. When it looks right, promote the same build to **Production**.

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
- [x] **Privacy policy URL** — see "Hosted pages" below
- [x] **Data deletion URL** — optional here (The Plate has no accounts), but
      provided anyway so the Data safety form has a clean answer
- [ ] Content rating questionnaire
- [ ] Target audience and content
- [ ] **Data safety form** — see below
- [ ] **Health apps declaration** — declare **Nutrition and Weight Management**.
      General educational wellness guidance: suggests common foods to add, does
      not diagnose or treat, makes no weight-loss claims, calculates no calories
- [ ] **AI-generated content** — disclose generative AI in the listing; the
      in-app reporting control is already built

### Hosted pages

One `docs/` directory, served from two hosts. Cloudflare Pages is the one to put
in the store listings — `platepatch.pages.dev` reads as a product; a
`github.io/PlateApp` path reads as a placeholder.

| Page | Cloudflare (use these) | GitHub Pages (fallback) |
|---|---|---|
| Privacy policy | `https://platepatch.pages.dev/privacy.html` | https://ramy888.github.io/PlateApp/privacy.html |
| Data deletion | `https://platepatch.pages.dev/delete-data.html` | https://ramy888.github.io/PlateApp/delete-data.html |
| Terms of use | `https://platepatch.pages.dev/terms.html` | https://ramy888.github.io/PlateApp/terms.html |
| Landing page | `https://platepatch.pages.dev/` | https://ramy888.github.io/PlateApp/ |

The pages name no store exclusively, so a single URL satisfies both Play and
App Store Connect.

**Deploying to Cloudflare Pages** (one-time login, then one command):

```bash
npx wrangler login                                   # opens a browser
npx wrangler pages project create platepatch --production-branch main
npx wrangler pages deploy docs --project-name platepatch --branch main
```

Re-run the last line after any edit to `docs/`. Pushing to `main` republishes
the GitHub Pages copy automatically.

The app also shows the same text on an in-app screen, so a broken link can never
strand a user.

### Data safety form

**This changed when the AI scan shipped.** Photos now leave the device. The full
table is in `STORE_LISTING.md`; the short version:

| Data type | Collected | Shared with |
|---|---|---|
| **Photos** | **Yes** | Google (Gemini) |
| Device or other IDs | Yes | RevenueCat |
| Purchase history | Yes | RevenueCat |
| Health and fitness | No | — |
| Personal info, location | No | — |

Encrypted in transit: yes. Data deletion: **yes** — in-app under
Settings → Delete my data, plus the deletion URL.

> Do **not** tick "processed ephemerally" for photos once the visual preview
> ships. Generated previews sit in R2 for up to 24 hours. That is accurate for
> recognition only.

### AI-generated content policy

Play requires in-app reporting for apps that generate content. The Plate has a
**Report this result** control on the confirm and result screens, and it must
stay on any new screen that shows an AI result.

### The paid Gemini tier is not optional

Google uses **free-tier** API content to improve its products; the **paid** tier
does not. The privacy policy states that photos are not used for training, which
is only true while billing is enabled on the Google Cloud project. If billing
ever lapses, that sentence becomes false and the policy must change with it.

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

## 8b. The iOS track

The iOS release build is **verified compiling** (`flutter build ios --release
--no-codesign` → `build/ios/iphoneos/Runner.app`, 39.5 MB). Bundle ID is already
`com.platepatch.app`. What remains is account work:

1. Apple Developer Program enrolment (started day one — see section 0).
2. App Store Connect → new app → bundle ID `com.platepatch.app`.
3. Subscriptions: a group with `platepatch_pro_monthly` and
   `platepatch_pro_yearly`, and a **7-day introductory free trial** on the
   yearly one. Same product IDs as Play keeps RevenueCat simple.
4. RevenueCat → add an **App Store** app to the same project → App Store Connect
   shared secret + in-app purchase key → attach the products to the same
   `platepatch_pro` entitlement and the same `default` offering.
5. Build with the iOS key:

   ```bash
   flutter build ipa --release --dart-define=REVENUECAT_IOS_KEY=appl_YOUR_KEY
   ```

6. Upload via Xcode or Transporter, then submit for review.

Nothing in the app hardcodes a store name: the privacy policy, the terms and the
"manage subscription" link all switch between Google Play and the App Store at
runtime. Apple rejects apps that mention a competing store, so do not
reintroduce a hardcoded one.

The hosted `docs/privacy.html` says "Google Play" — before submitting to Apple,
edit that one line to say "the App Store", or reword it to "your app store" so a
single URL serves both listings.

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
- [ ] Build-in-public links — repo is public at
      https://github.com/Ramy888/PlateApp

One rule worth repeating: **do not use the influencer's name, photo, voice,
branding or logo** anywhere in the app, the listing, or the marketing. The
official rules prohibit it without written permission.
