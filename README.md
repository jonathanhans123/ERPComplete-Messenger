# ERPComplete Messenger

Cross-platform **Flutter** app for ERPComplete messaging (chat + LiveKit video). One codebase for Android and iOS.

## Stack

- Flutter 3.16+
- Laravel API `/api/v1/messaging/*`
- LiveKit (native SDK in phase 2)
- Reverb websocket (phase 2)

## Default API

`https://srv1804550.hstgr.cloud/api/v1`

## First-time setup

Install [Flutter](https://docs.flutter.dev/get-started/install), then:

```bash
cd ERPComplete-Messenger
flutter pub get
# Generate android/ and ios/ if missing:
flutter create . --org com.erpcomplete --project-name erpcomplete_messenger
flutter run
```

## Related repos

| Repo | Role |
|------|------|
| ERPComplete | Laravel API |
| ERPComplete-RFID | Android RFID |
| ERPComplete-RFID-iOS | iOS RFID |

## Phase 1

- [x] Login (Passport bearer)
- [x] Conversations list (read-only MVP)
- [ ] Chat thread + send message
- [ ] LiveKit video calls
- [ ] E2E encryption (match web crypto)
