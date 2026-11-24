# Collaborative Field Engineer

An offline-first Flutter field-survey platform that allows authorized users to create and manage survey data locally, then securely synchronize queued changes with Firebase when connectivity returns.

## Core Features

- Google authentication
- Firebase workspace authorization
- Locally cached workspace access
- 24-hour offline authorization limit
- Survey-site creation and management
- Observation creation, editing, and deletion
- SQLite offline persistence
- Durable synchronization queue
- Automatic synchronization after connectivity restoration
- Retry and backoff handling
- Version-vector conflict tracking
- Firebase App Check integration
- Firebase security-rule tests

## Offline-First Workflow

1. The user creates, updates, or deletes a survey site or observation.
2. The change is saved immediately in SQLite.
3. The local record receives a `pending` synchronization status.
4. A corresponding operation is inserted into the durable sync queue.
5. The user can continue working without an internet connection.
6. Synchronization remains locked until workspace membership is verified online.
7. When connectivity and authorization are restored, queued operations are sent to Firebase.
8. Successful operations are marked as `synced`.
9. Temporary failures are scheduled for retry.
10. Conflicting changes are preserved for resolution.

## Synchronization States

| Status | Meaning |
|---|---|
| `pending` | Stored locally and waiting to synchronize |
| `processing` | Currently being processed by the sync engine |
| `synced` | Successfully stored remotely |
| `failed` | Synchronization failed and requires attention |
| `conflict` | Local and remote versions require resolution |

## Architecture

The platform separates responsibilities across:

- **SQLite database** — stores sites, observations, metadata, and queued operations
- **Repositories** — save local records and enqueue matching sync operations
- **Sync queue** — preserves pending operations across application restarts
- **Sync engine** — processes operations and handles success, retry, failure, and conflict results
- **Firebase remote data source** — applies changes to the remote workspace
- **Automatic sync coordinator** — monitors connectivity and starts synchronization
- **Version vectors** — track distributed changes across replicas
- **Authorization cache** — permits temporary offline access only for the matching verified user
- **Authorization guard** — prevents synchronization until membership is revalidated online
- **Presentation layer** — displays authentication, sites, observations, sync states, and errors

## Security Model

- Users authenticate using Google Sign-In and Firebase Authentication.
- Workspace membership and roles are validated using Firebase.
- Verified authorization is cached locally for limited offline access.
- Cached authorization expires after 24 hours.
- One user cannot use another user’s cached authorization.
- Offline users may continue local work, but remote synchronization remains disabled.
- Firebase App Check protects access to backend resources.
- Firebase security rules provide server-side authorization enforcement.

## Technologies

- Flutter
- Dart
- SQLite
- Firebase Authentication
- Firebase Realtime Database
- Firebase App Check
- Google Sign-In
- Connectivity monitoring
- Repository pattern
- Dependency injection
- Version vectors
- Flutter Test
- Firebase security-rule testing

## Firebase Setup

Connect the project to your own Firebase configuration:

```bash
flutterfire configure
flutter pub get
```

For Android development, add the required debug signing fingerprints to Firebase. App Check debug tokens must be registered through Firebase Console and must never be committed to source control.

## Running the Application

```bash
flutter pub get
dart format lib test
flutter analyze
flutter test
flutter run
```

## Testing

The project includes tests covering:

- SQLite repositories
- Sync queue operations
- Sync-engine success and failure handling
- Retry behavior
- Offline observation creation and updates
- Workspace authorization caching
- Authorization expiration
- User-specific cached access
- Firebase security rules

Firebase rule tests are located in:

```text
firebase_rules_tests/
```

The generated `node_modules` directory is intentionally excluded from version control.

## What I Learned

This project strengthened my understanding of offline-first architecture, durable synchronization queues, SQLite transactions, Firebase security, retry strategies, distributed version tracking, connectivity-aware execution, repository design, dependency injection, and automated testing.
