# CampusOne — ERP-based Integrated Student Management System

Flutter + Firebase multi-tenant ERP for colleges. Modules: students, fees, hostel, exams, results, notifications, dashboards. Secure Firestore rules and Cloud Functions.

## Tech
- Flutter, Riverpod, fl_chart
- Firebase: Auth, Firestore, Storage, Functions

## Setup
1) Install Flutter and Dart.
2) Firebase CLI: `npm i -g firebase-tools` and login: `firebase login`.
3) Configure Firebase for this app:
   - `dart pub global activate flutterfire_cli`
   - `flutterfire configure --platforms=web,android,ios`
   - Place platform configs (NOT committed):
     - `android/app/google-services.json`
     - `ios/Runner/GoogleService-Info.plist`
4) Get packages: `flutter pub get`
5) Run web: `flutter run -d chrome`

## Firestore rules and indexes
- Rules: `firestore.rules`
- Indexes: `firestore.indexes.json`

Deploy rules:
```bash
firebase deploy --only firestore:rules
```

## Demo data
Node scripts (use env, keep keys private):
```bash
# Windows PowerShell example
$env:SA_PATH="C:\Users\hp\Downloads\campusone-76fbd-0b84ff9f0a69.json"; $env:FB_PROJECT="campusone-76fbd"
node tools/seed_rooms.js demo $env:SA_PATH
```

## Modules (where code lives)
- Auth/routing: `lib/core/app_providers.dart`, `lib/core/router.dart`, `lib/screens/auth/`
- Students: `lib/models/student.dart`, `lib/services/student_service.dart`, `lib/screens/admin/*student*`
- Fees: `lib/models/fee.dart`, `lib/services/fee_service.dart`, `lib/screens/admin/fees_screen.dart`
- Hostel: `lib/models/room.dart`, `lib/services/room_service.dart`, `lib/screens/admin/rooms_grid_screen.dart`
- Exams/Results: services + screens under `lib/services/` and `lib/screens/`
- Functions: `functions/src/index.ts`

## Build
- Web: `flutter build web`
- Android: `flutter build apk`
- iOS: `flutter build ios`

## Secrets policy
Do NOT commit:
- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`
- `tools/*.json` service-account keys

Safe to commit: all Flutter code, `lib/firebase_options.dart`, rules, indexes, Functions code.

## License
MIT — see `LICENSE`.
