# Gym Log

SwiftUI + SwiftData iOS gym tracker (iOS 17+): 4-day push/pull/legs/upper split, per-lift weight logging with "go up" suggestions, rest timer, progress charts, workout calendar, multiple people, training-day reminders, a home screen widget, and backup/restore (auto-backup to an iCloud Drive folder, JSON export, CSV export).

## Build
Every push runs **Actions → Build IPA** on a GitHub macOS runner (XcodeGen + xcodebuild, unsigned). Download the **GymLog-ipa** artifact from the finished run and sign it with your own certificate.

The project file is generated from `project.yml`; `make-icon.sh` builds the app icon from `AppIcon.png` during generation.
