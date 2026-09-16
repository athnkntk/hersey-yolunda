# Herşey Yolunda — Project Rules

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
- Production requires DATABASE_URL, DATA_ENCRYPTION_KEY (32-byte hex), LOOKUP_KEY. Signup has no SMS dependency. Apple-linked recovery is not implemented; never imply it is available.
- Invitations accept either a 256-bit token/link or a rate-limited 12-character code, not an account ID. Owner authorization is mandatory. QR generation uses CoreImage and requests no camera permission.
- APNs transport requires explicit APNS_ENABLED=true and production credentials; local tests inject a fake transport.
- Dependencies are pinned. Multer 2.3.0 override addresses advisories in Nest's transitive dependency. Do not bypass security checks or enable dependency install scripts without reviewing them.
- Schema migrations are versioned in database.ts. All MVP transactions currently serialize via an advisory lock; do not claim production scalability without load testing.

## iOS

- Regenerate the Xcode project: xcodegen generate in ios/.
- Shared code is compiled into both the application and widget. Tokens belong in the shared Keychain, not UserDefaults.
- The app links FirebaseCore + FirebaseMessaging via SPM (firebase-ios-sdk from 12.5.0); GoogleService-Info.plist lives in ios/App/. The widget does not link Firebase. FCM token is stored in UserDefaults under "fcmToken" until the Functions port consumes it.
- Release API URL is deliberately unset. Debug currently has a physical-device LAN address from prior setup; simulator verification overrides HY_API_URL=http://127.0.0.1:3100/v1. No production HTTP broadening.
- Isolated test API: LOCAL_DATABASE_PATH=/tmp/hersey-name-auth-db PORT=3100 HOST=127.0.0.1 node --import tsx src/main.ts. HTTP tests use HY_TEST_API_URL=http://127.0.0.1:3100/v1.
- Registration is rate limited to 10 accounts/hour per IP hash. Repeated iOS test-suite runs against one long-lived local server can exhaust this; restart with a fresh LOCAL_DATABASE_PATH or run tests against the less-used 3000 server. Do not weaken the limit itself.
- Do not silently restore, delete, or replace the existing backend/.data.bak-* database. The former setup moved it before this auth revision; v5 migration is tested on fixtures, not claimed applied to that backup.
- Build/test simulator with ad-hoc signing to preserve App Group entitlements: CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-.
- Put DerivedData outside Documents, e.g. /tmp/HerSeyYolundaDerived; Finder extended attributes in Documents caused signing errors.
- Example verification: xcodebuild -project HerseyYolunda.xcodeproj -scheme HerseyYolunda -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/HerSeyYolundaNameAuth HY_API_URL=http://127.0.0.1:3100/v1 CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- -parallel-testing-enabled NO test.
- Real iPhone (must be paired and connected): build with DEVELOPMENT_TEAM=2HBFPNCMR8 -allowProvisioningUpdates for generic/platform=iOS, then `xcrun devicectl device install app --device 2CB88C1D-376E-519E-B958-7E3FA4117BCF <app>` and `... device process launch --device <id> com.herseyyolunda.app`. The phone reaches the Mac's LAN API via http://192.168.1.7:3000/v1 (Debug only, same Wi-Fi; LAN backend: HOST=0.0.0.0 npm run dev).

## Deployment

- Firebase decision (v1.4): backend moves to Cloud Functions + Firestore + FCM + Cloud Scheduler; see the v1.4 record in PLAN.md section 33 and firebase.json / firestore.rules / functions/ at repo root.
- Scaffolding validated by JSON syntax checks only; versions in functions/package.json must be pinned and verified at first `firebase deploy`.
- The user must create the Firebase project, enable Blaze, select europe-west1 for Firestore, and download GoogleService-Info.plist — these require their Google account.
- The Docker/Caddy stack (docker-compose.yml, web/) remains as an alternative; it is no longer the primary path after the Firebase decision.
- web/public contains the invite landing page and .well-known/apple-app-site-association; web/Caddyfile serves AASA as application/json, rewrites /invite to the landing page and proxies /v1/* to the api.
- Docker is not installed locally: compose/Caddy/Dockerfile are validated by syntax checks only; end-to-end TLS verification must run on the live server.
- HTTPS invite links activate only after: domain + DNS + live server, Associated Domains entitlement (applinks:<domain>) in Xcode, and HY_INVITE_DOMAIN set in ios/project.yml. Until then the app falls back to the herseyyolunda:// custom scheme.
- App Store URL placeholder lives in web/public/index.html (APP_STORE_URL constant); update it only when the listing is live.
- UI integration tests require the local backend running first.
- Real-device signing, APNs, minimum OS coverage, VoiceOver usability and TestFlight require separate verification and cannot be inferred from simulator tests.

## Completion

- Run relevant tests after each logical change. Update PLAN.md with commands/results and unresolved limitations.
- Do not claim legal compliance, user-study success, App Store approval, push delivery or successful restore tests without evidence.
