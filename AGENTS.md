# Herşey Yolunda — Project Rules

## Project location

- The project lives at `~/Herşey Yolunda` (NOT ~/Documents — iCloud Desktop&Documents sync caused multi-second file-read stalls and random hangs; do not move it back into an iCloud-synced folder).
- Debug LAN API host is `Atahan-MacBook-Air.local` (IP-independent via mDNS; NSAllowsLocalNetworking covers it). LAN backend: HOST=0.0.0.0 npm run dev in backend/.
- Production target is Render + Supabase/Postgres (see render.yaml and the 16 September 2026 record in PLAN.md section 33: Render free web service `hersey-yolunda-api` on the Supabase Supavisor session pooler, SCHEDULER_MODE=external). The GitHub Actions workflow .github/workflows/tick.yml pings /v1/tick every 10 minutes using secrets.TICK_SECRET and vars.API_URL.
- Set them after deploy: gh secret set TICK_SECRET; gh variable set API_URL https://<service>.onrender.com

## Scope

- PLAN.md is the source of truth. Mark a checkbox only after verifying its acceptance criteria; record local-only verification separately from production readiness.
- Native SwiftUI iOS 17+ application and WidgetKit extension are in ios/. NestJS API is in backend/.
- No location, health measurements, camera, microphone, contact scraping, automatic passive check-in, ads, or payments in the MVP.
- User declarations are not safety verification. Never display successful check-in before the server acknowledges it.
- Never enable production SMS/APNs, create paid accounts, or deploy without the user's provider/account decisions.

## Backend

- Install: npm ci in backend/.
- Typecheck and isolated database tests: npm run verify in backend/.
- Dependency audit: npm audit in backend/.
- Local server: npm run dev in backend/ (127.0.0.1:3000).
- HTTP integration tests against the local server: npm run test:http in backend/.
- Accounts are created by name + enabled preference via POST /auth/device. A random device-held bootstrap secret supports retry for 10 minutes; names and account IDs are never credentials. Old OTP endpoints return 410 in every environment.
- Local mode uses PGlite in backend/.data by default; LOCAL_DATABASE_PATH selects a separate development database. Preserve existing backups. Use synthetic names only.
- Production requires DATABASE_URL, DATA_ENCRYPTION_KEY (32-byte hex), LOOKUP_KEY. Signup has no SMS dependency. User-held recovery keys are implemented (`HYR1.` + 32-byte base64url; `GET/PUT/DELETE /me/recovery-key`, unauthenticated `POST /auth/recover` which rotates the key and revokes old sessions). Apple-linked recovery is still NOT implemented; never imply it is available.
- Production trusts exactly one proxy hop (Render): `app.set('trust proxy', 1)` is applied only when NODE_ENV=production, immediately after NestFactory.create; development/test keep the Express default. Registration/recovery rate limits rely on `request.ip` — never enable `trust proxy` broadly or trust arbitrary leftmost X-Forwarded-For.
- Invitations accept either a 256-bit token/link or a rate-limited 12-character code, not an account ID. Owner authorization is mandatory. QR generation uses CoreImage and requests no camera permission.
- APNs transport requires explicit APNS_ENABLED=true and production credentials; local tests inject a fake transport.
- Dependencies are pinned. Multer 2.4.0 override keeps Nest's transitive dependency at the first patched version (GHSA-3pph-fpjx-jg34). Do not bypass security checks or enable dependency install scripts without reviewing them.
- Schema migrations are versioned in database.ts. All MVP transactions currently serialize via an advisory lock; do not claim production scalability without load testing.

## iOS

- Regenerate the Xcode project: xcodegen generate in ios/.
- Shared code is compiled into both the application and widget. Tokens belong in the shared Keychain, not UserDefaults.
- The app and widget are bilingual (Turkish/English) via `ios/Shared/{tr,en}.lproj/Localizable.strings`; the in-app language override lives in `L10n` and persists across launches. The unused Firebase SDK was removed; Firebase scaffolding at the repo root is historical/inactive (see Deployment).
- Release API URL is https://hersey-yolunda-api.onrender.com/v1 (project.yml); Debug uses the Mac LAN host; simulator verification overrides HY_API_URL=http://127.0.0.1:3100/v1. No production HTTP broadening.
- Versions live only in project.yml (MARKETING_VERSION / CURRENT_PROJECT_VERSION) and reach both Info.plists via explicit `CFBundleShortVersionString: $(MARKETING_VERSION)` / `CFBundleVersion: $(CURRENT_PROJECT_VERSION)` entries in `info.properties`; never hand-edit the generated Info.plist (xcodegen overwrites it with literal 1.0/1, which is how the live "1.0 (4)" build shipped under ASC version 0.2.0). Any new upload must have CFBundleShortVersionString > 1.0 (ITMS-90062).
- App Store upload: `xcodebuild … -configuration Release -destination 'generic/platform=iOS' -archivePath /tmp/hy-release/HerseyYolunda.xcarchive -allowProvisioningUpdates -authenticationKeyPath ~/private_keys/AuthKey_5XR3QN2NJ6.p8 -authenticationKeyID 5XR3QN2NJ6 -authenticationKeyIssuerID <issuer> archive`, then `-exportArchive` with an ExportOptions.plist (method app-store-connect, destination upload, teamID 2HBFPNCMR8, signingStyle automatic, manageAppVersionAndBuildNumber=false). `aps-environment` is `development` in the entitlements and flips to production at export; the App ID has the Push Notifications capability.
- Isolated test API: LOCAL_DATABASE_PATH=/tmp/hersey-name-auth-db PORT=3100 HOST=127.0.0.1 node --import tsx src/main.ts. HTTP tests use HY_TEST_API_URL=http://127.0.0.1:3100/v1.
- Registration is rate limited to 10 accounts/hour per IP hash. Repeated iOS test-suite runs against one long-lived local server can exhaust this; restart with a fresh LOCAL_DATABASE_PATH or run tests against the less-used 3000 server. Do not weaken the limit itself.
- Do not silently restore, delete, or replace the existing backend/.data.bak-* database. The former setup moved it before this auth revision; v5 migration is tested on fixtures, not claimed applied to that backup.
- Build/test simulator with ad-hoc signing to preserve App Group entitlements: CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-.
- Put DerivedData outside Documents, e.g. /tmp/HerSeyYolundaDerived; Finder extended attributes in Documents caused signing errors.
- Example verification: xcodebuild -project HerseyYolunda.xcodeproj -scheme HerseyYolunda -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/HerSeyYolundaNameAuth HY_API_URL=http://127.0.0.1:3100/v1 CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- -parallel-testing-enabled NO test.
- Real iPhone (must be paired and connected): build with DEVELOPMENT_TEAM=2HBFPNCMR8 -allowProvisioningUpdates for generic/platform=iOS, then `xcrun devicectl device install app --device 2CB88C1D-376E-519E-B958-7E3FA4117BCF <app>` and `... device process launch --device <id> com.herseyyolunda.app`. The phone reaches the Mac's LAN API via http://192.168.1.7:3000/v1 (Debug only, same Wi-Fi; LAN backend: HOST=0.0.0.0 npm run dev).

## Deployment

- Active path (D-015): Render web service `hersey-yolunda-api` + Supabase/Postgres per render.yaml; `SCHEDULER_MODE=external`, GitHub Actions `/v1/tick` keeps it warm. Backend v6 (timezone + localization) must deploy BEFORE the 1.1.0 app ships: the old server rejects the new `/auth/device` timezone field.
- Firebase migration (v1.4 record) is historical/inactive: firebase.json / firestore.rules / functions/ remain as scaffolding at the repo root, but Render+Supabase superseded that decision and the iOS Firebase SDK was removed. Do not treat it as the active backend.
- The Docker/Caddy stack (docker-compose.yml, web/) remains as an alternative self-host path.
- web/public contains the bilingual invite landing page and .well-known/apple-app-site-association; web/Caddyfile serves AASA as application/json, rewrites /invite to the landing page and proxies /v1/* to the api. docs/ contains the bilingual support + privacy pages (docs/site.js language switching).
- Docker is not installed locally: compose/Caddy/Dockerfile are validated by syntax checks only; end-to-end TLS verification must run on the live server.
- HTTPS invite links activate only after: domain + DNS + live server, Associated Domains entitlement (applinks:<domain>) in Xcode, and HY_INVITE_DOMAIN set in ios/project.yml. Until then the app falls back to the herseyyolunda:// custom scheme.
- App Store URL placeholder lives in web/public/index.html (APP_STORE_URL constant); update it only when the listing is live.
- UI integration tests require the local backend running first.
- Real-device signing, APNs, minimum OS coverage, VoiceOver usability and TestFlight require separate verification and cannot be inferred from simulator tests.

## Completion

- Run relevant tests after each logical change. Update PLAN.md with commands/results and unresolved limitations.
- Do not claim legal compliance, user-study success, App Store approval, push delivery or successful restore tests without evidence.
## Store screenshots

- The `AppStoreScreenshots` test is opt-in: it skips unless `HY_CAPTURE_STORE_SCREENSHOTS=1` (TEST_RUNNER_ prefixed equivalent also works); screenshot language is `HY_SCREENSHOT_LOCALE` (tr|en, default tr).
- Capture: Release + production API, per simulator (`iPhone 17 Pro Max`, `iPad Pro 13-inch (M5)`) and per locale (tr|en):
  `xcodebuild -project HerseyYolunda.xcodeproj -scheme HerseyYolunda -configuration Release -destination 'platform=iOS Simulator,name=<device>' -derivedDataPath /tmp/HerSeyYolundaAudit HY_API_URL=https://hersey-yolunda-api.onrender.com/v1 ENABLE_TESTABILITY=YES CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- -parallel-testing-enabled NO -only-testing:YolundaUITests/AppStoreScreenshots/testCaptureStoreScreenshots -resultBundlePath /tmp/hy-shots-<dev>-<locale>.xcresult TEST_RUNNER_HY_API_URL=https://hersey-yolunda-api.onrender.com/v1 TEST_RUNNER_HY_CAPTURE_STORE_SCREENSHOTS=1 TEST_RUNNER_HY_SCREENSHOT_LOCALE=<locale> test`
- Status bar: keep `while true; do xcrun simctl status_bar <udid> override --time "9:41" --dataNetwork wifi --wifiBars 3 --cellularBars 4 --batteryLevel 100; sleep 5; done` running during the test; kill it after. Verify with `xcrun simctl io <udid> screenshot` first.
- Export raw PNGs: `xcrun xcresulttool export attachments --path /tmp/hy-shots-<dev>.xcresult --output-path /tmp/hy-raw/<iphone|ipad>/` then rename per manifest.json.
- Seed reuse (rate limit is 10 registrations/hour/IP; each fresh run registers Ayşe): refresh Fatma/Mehmet tokens host-side via POST /auth/refresh, then `xcrun simctl spawn <udid> launchctl setenv HY_SEED_FATMA_AT <access>` / `HY_SEED_MEHMET_AT <access>` / `HY_SEED_KEEP 1`. Without them the test registers seeds and deletes them in tearDown; with KEEP it skips seed deletion — delete via DELETE /me {"confirmation":"HESABIMI SİL"}. UIPasteboard is unusable in the runner (deadlocks on paste consent).
- Invitation `label` must be one of the backend enum values (Oğlum, Kızım, Eşim, Kardeşim, Torunum, Yakınım, Diğer); anything else (e.g. "Annem") is a 400 invalid_input. The test seeds Ayşe's share_mine invitation accepted by Fatma to populate "Benim haberimi alanlar".
- Compose: `/tmp/hy-venv/bin/python scripts/store_screenshots.py --locale <tr|en> --raw /tmp/hy-raw --out ios/StoreAssets/screenshots` (venv: `python3 -m venv /tmp/hy-venv && /tmp/hy-venv/bin/pip install pillow`). Local review captures (not production) live under `ios/StoreAssets/1.1.0/review-screenshots/`.
