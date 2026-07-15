# NCD Tracker App

A cross-platform Flutter application designed for DHIS2 data collection and tracking with offline support, automatic synchronization, and desktop compatibility.

## Overview

The DHIS2 Tracker App enables users to collect, manage, and synchronize health or program data efficiently across multiple platforms. The application supports offline data storage using SQLite and automatically synchronizes records when network connectivity becomes available.

Built with Flutter, the app runs on:

- Android
- iOS
- Windows
- Linux
- macOS

## Features

### Offline-First Architecture
- Local SQLite database storage
- Continue working without an internet connection
- Secure local data persistence

### Automatic Synchronization
- Background network monitoring
- Automatic sync when connectivity is restored
- Data consistency between local storage and remote server

### Cross-Platform Support
- Mobile support (Android & iOS)
- Desktop support (Windows, Linux, macOS)
- Shared codebase across all platforms

### Modern User Experience
- Material 3 design
- Custom splash screen
- Clean and responsive interface

## Technology Stack

### Frontend
- Flutter
- Dart

### Local Database
- SQLite
- sqflite_common_ffi (Desktop Support)

### Architecture Components
- Splash Screen Module
- Sync Manager Service
- Local Data Storage
- Network Synchronization

## Project Structure

```text
lib/
├── main.dart
├── screens/
│   └── splash_screen.dart
├── services/
│   └── sync_manager.dart
└── ...
```

## Getting Started

### Prerequisites

- Flutter SDK
- Dart SDK
- Android Studio or VS Code
- Git

Verify Flutter installation:

```bash
flutter doctor
```

## Installation

Clone the repository:

```bash
git clone https://github.com/your-username/dhis2-tracker-app.git
cd dhis2-tracker-app
```

Install dependencies:

```bash
flutter pub get
```

Run the application:

```bash
flutter run
```

## Desktop Support

The application automatically initializes SQLite FFI when running on:

- Linux
- Windows
- macOS

This ensures local database functionality is available on desktop environments.

## Application Flow

```text
Application Launch
        │
        ▼
  Splash Screen
        │
        ▼
 Service Initialization
        │
        ├── Database Setup
        └── Sync Manager Setup
        │
        ▼
 Main Application
        │
        ▼
 Data Collection & Tracking
        │
        ▼
 Automatic Synchronization
```

## Dependencies

Example key packages used:

```yaml
flutter:
sqflite_common_ffi:
```

Additional dependencies may be found in `pubspec.yaml`.

## Development

Run in debug mode:

```bash
flutter run
```

Build release version:

### Android

```bash
flutter build apk --release
```

### Windows

```bash
flutter build windows
```

### Linux

```bash
flutter build linux
```

### macOS

```bash
flutter build macos
```

## Future Enhancements

- DHIS2 API integration improvements
- Advanced conflict resolution during synchronization
- User authentication and role management
- Data visualization dashboards
- Push notifications
- Audit logging

## License

This project is licensed under the MIT License.

## Author

Developed using Flutter and Dart for efficient DHIS2 data collection, tracking, and synchronization.
