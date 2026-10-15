# Store package — 1.1.0 (local draft, 15 October 2026)

Status: **local draft only**. Nothing here has been written to App Store Connect; the live app is still 1.0.2 (`READY_FOR_SALE`, tr + en-GB locales only). Keyword popularity was not measured; title availability and Apple review were not verified; no ASO score or forecast is claimed.

## Contents

| File / directory | Description |
|---|---|
| `metadata.json` | Store metadata draft: app `6812729799`, version `1.1.0`, build `10`. Locales `tr`, `en-US`, `en-GB` — names, subtitles, keywords, promotionalText, descriptions, whatsNew (includes recovery key), support/privacy URLs, plus subscription `premium_monthly` (group `22389833`) localizations. Marked `local-draft`. |
| `review-screenshots/{tr,en}/` | **Local review captures**, not production proof: composed 6.9″ iPhone, 6.5″ iPhone and 13″ iPad sets (6 scenes each) + `preview-iphone.png` / `preview-ipad.png` contact sheets, per locale. |

Known ASC deltas this draft resolves: live app is 1.0.2; en-GB copy is currently Turkish; subscription `6812755028` is approved with only `tr` localization and its description incorrectly says "unlimited". None of that has been changed on ASC.

All fields in `metadata.json` — including the subscription display names and descriptions for `tr`/`en-US`/`en-GB` (`Premium Aylık` / `Premium Monthly`, group `Premium`) — are the approved final local draft copy. Field lengths re-verified within ASC limits (TR name 13 / EN names 15 / descriptions 45 chars).

## Screenshot pipeline

Raw captures came from local Release builds (`ENABLE_TESTABILITY=YES`) on iPhone 17 Pro Max and iPad Pro 13-inch (M5) simulators against a local TLS proxy (loopback test root cert trusted only inside those simulators; no product ATS/TLS changes). The `AppStoreScreenshots` UI test is opt-in: `HY_CAPTURE_STORE_SCREENSHOTS=1`, `HY_SCREENSHOT_LOCALE=tr|en`.

Compose (per locale):

```bash
/tmp/hy-venv/bin/python scripts/store_screenshots.py \
  --locale tr --raw /tmp/hy-global-raw/tr --out ios/StoreAssets/1.1.0/review-screenshots/tr
/tmp/hy-venv/bin/python scripts/store_screenshots.py \
  --locale en --raw /tmp/hy-global-raw/en --out ios/StoreAssets/1.1.0/review-screenshots/en
```

Result bundles: `/tmp/hy-shots-iphone-tr.xcresult`, `/tmp/hy-shots-ipad-tr.xcresult` (Turkish), `/tmp/hy-shots-iphone-en2.xcresult`, `/tmp/hy-shots-ipad-en2.xcresult` (English, recaptured after the catalog greeting fix — final artwork shows “Hello, Sarah”, OCR-verified on both devices). Raw exports under `/tmp/hy-global-raw/{tr,en}/{iphone,ipad}/`.

**Production recapture (separate gate):** after backend v6 deploys, rerun the same Release captures against `https://hersey-yolunda-api.onrender.com/v1` (the AGENTS.md "Store screenshots" command) and place finals under `ios/StoreAssets/1.1.0/screenshots/{tr,en}/` before upload.

## Verified locally (15 October 2026)

- Backend `npm run verify`: **56/56 passed**. `npm run test:http` against `http://127.0.0.1:3110/v1`: **2/2** (Accept-Language tr/en localization, Content-Language + X-Server-Time, timezone registration `America/Los_Angeles`, unauthenticated `/invitations/preview` → 401 boundary).
- `npm audit --audit-level=moderate`: **0 vulnerabilities** after the Multer override moved to exact **2.4.0** (first patched for GHSA-3pph-fpjx-jg34).
- iOS full suite (iPhone 17, API on 3110): **57 passed, 2 skipped (opt-in captures), 0 failed** — `/tmp/hy-full-core.xcresult`. Includes Turkish UI, English switch/relaunch, large text, widget IntentIntegrationTests, InvitationTests, all unit classes.
- Screenshot captures: Turkish flows passed earlier (iPhone 17 Pro Max + iPad Pro 13″, `/tmp/hy-shots-{iphone,ipad}-tr.xcresult`). English flows **recaptured** after the catalog greeting fix — `/tmp/hy-shots-iphone-en2.xcresult`, `/tmp/hy-shots-ipad-en2.xcresult`, both `TEST SUCCEEDED`; OCR of `02-ana-ekran.png` shows **"Hello, Sarah"** on both devices. Composed EN outputs in `review-screenshots/en/` reflect the corrected greeting.
- Static pages: Chrome DevTools Protocol device emulation (`Emulation.setDeviceMetricsOverride`, mobile) at **390 px and 320 px** widths — `documentElement.clientWidth` equals the requested width and `scrollWidth <= clientWidth` for support, privacy and invite pages in **both** `?lang=tr` and `?lang=en`, before and after real language-button clicks. Invite token states: missing / malformed / duplicate → "Open in app" disabled; one well-formed 43-char token → enabled (click builds `herseyyolunda://invite?token=`). **Zero** requests to `/invitations/status` or any invitation API observed via the Network domain. Fresh captures: `/tmp/hy-invite-en-mobile.png`, `/tmp/hy-support-en-mobile.png` (+ tr variants).
- Archive: `/tmp/hy-global-release/HerseyYolunda-final.xcarchive` — generic/platform=iOS Release, team `2HBFPNCMR8`, `ARCHIVE SUCCEEDED`.
- Exported IPA (local export only, `destination=export`, nothing uploaded): `/tmp/hy-global-release/export/HerseyYolunda.ipa` — app+widget **1.1.0 (9)**, `HYAPIURL=https://hersey-yolunda-api.onrender.com/v1`, `en.lproj`+`tr.lproj` in both bundles, decoded greetings `Hello,\n%@` / `Merhaba,\n%@`, `PrivacyInfo.xcprivacy` in both, **no Firebase**. Signed **Apple Distribution** with "iOS Team Store Provisioning Profile" for both app and widget; `aps-environment=production`, `get-task-allow=false`, no `ProvisionedDevices`/`ProvisionsAllDevices` keys. **This IPA predates the recovery-key batch (build 10)** — a fresh archive/export is part of the post-deploy production stage.
- `git diff --check`, JSON/plist/JS syntax checks: clean.

## Deployment order (hard requirement)

**Backend v6 must deploy before this app ships.** The live server has the strict `/auth/device` schema and rejects the new `timezone` field. Order: (1) deploy backend v6 to Render, verify `/v1/health` + migrations; (2) production screenshot recapture; (3) write this metadata to ASC, attach screenshots, export + upload a distribution-signed archive; (4) submit for review.

## Not verified — do not claim

- Real-device installation, VoiceOver / older-device accessibility, pilot/user validation.
- APNs credentials and actual push delivery (`push_configured=false` everywhere).
- StoreKit purchase/restore on a real App Store account; subscription verification was not re-run against ASC.
- Production deployment, Supabase/Render backup validation, hosting limits under load.
- Legal/privacy review; App Store approval; title availability; keyword performance.
