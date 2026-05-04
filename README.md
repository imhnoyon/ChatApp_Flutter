# ChatApp Flutter

A full-featured Flutter messaging app matching the ChatApp web interface. Same API, same WebSocket connection, same features.

---

## Features

- ✅ Login & Registration
- ✅ Conversations list with unread badge, last message preview
- ✅ Real-time messaging via WebSocket
- ✅ Typing indicators
- ✅ Online/offline status
- ✅ Read receipts (✓ / ✓✓ blue)
- ✅ Message reactions (long press a message)
- ✅ Edit your own text messages
- ✅ Send images from gallery
- ✅ Voice messages (hold the mic button)
- ✅ Audio playback with progress bar
- ✅ Dark / Light theme toggle
- ✅ Optimistic UI (messages show instantly)
- ✅ Auto-reconnect WebSocket

---

## Setup

### 1. Install Flutter
If you don't have Flutter installed:
```
https://docs.flutter.dev/get-started/install
```
Flutter SDK 3.10+ is required.

### 2. Get dependencies
```bash
cd chatapp
flutter pub get
```

### 3. Run the app

**Android:**
```bash
flutter run
```

**iOS (Mac only):**
```bash
cd ios && pod install && cd ..
flutter run
```

**Release APK (Android):**
```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

---

## API Base URL

The default API base is:
```
https://rs0hfx59-8003.asse.devtunnels.ms
```

To change it, edit `lib/services/api_service.dart`:
```dart
const String kDefaultApiBase = 'https://your-api-url.com';
```

---

## API Endpoints Used

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | /api/auth/login/ | Login |
| POST | /api/auth/register/ | Register |
| GET | /api/auth/me/ | Current user info |
| GET | /api/conversations/ | List conversations |
| POST | /api/conversations/ | Create conversation |
| GET | /api/conversations/:id/messages/ | Get messages |
| POST | /api/conversations/:id/upload/ | Upload image/voice |
| PATCH | /api/conversations/:id/messages/:id/edit/ | Edit message |
| GET | /api/users/ | List all users |

**WebSocket:** `wss://your-api/ws/chat/:convId/?token=<jwt>`

### WebSocket Actions Sent
- `send_message` — send text
- `typing` — typing indicator
- `seen` — mark seen
- `mark_read` — mark all read
- `react` — emoji reaction
- `presence_ping` / `presence_pong` — online status

### WebSocket Events Received
- `message` — new message
- `typing` — other user typing
- `seen` — message seen
- `reaction` — emoji reaction updated
- `status` — online/offline
- `message_status` — delivered/seen status update

---

## Project Structure

```
lib/
  main.dart                    # App entry, theme toggle, auth guard
  theme.dart                   # Dark/light colors and ThemeData
  models/
    models.dart                # User, Message, Conversation, Reaction
  services/
    api_service.dart           # HTTP REST API calls
    socket_service.dart        # WebSocket manager with reconnect
  screens/
    auth_screen.dart           # Login & Register tabs
    conversations_screen.dart  # Chat list sidebar
    chat_screen.dart           # Message view + footer
  widgets/
    message_bubble.dart        # Message UI (text/image/voice/reactions/edit)
```

---

## Permissions Required

**Android** (`AndroidManifest.xml`):
- `INTERNET`
- `RECORD_AUDIO`
- `READ_EXTERNAL_STORAGE`
- `CAMERA`

**iOS** (`Info.plist`):
- Microphone usage description
- Photo library usage description
- Camera usage description

---

## Voice Messages

- **Hold** the mic button (bottom right) to record
- **Release** to send
- Recorded as `.m4a` (AAC) on iOS/Android
- Plays back inline with progress bar

## Images

- Tap the **paperclip icon** → Photo
- Picks from gallery and uploads to server
