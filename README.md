# DigitalGuest Breakfast Orders

A Windows breakfast-order manager built with Flutter and Material 3 Expressive.
Imports DigitalGuest order emails, reviews unmatched items and cabins, manages menus,
and prints orders, delivery schedules, item totals and timetables.

## Download

[Download the latest Windows release](https://github.com/RobinPopkema/Digitalguest-breakfast-orders/releases/latest).
Extract the entire Windows ZIP and run breakfast_orders.exe. Windows 10/11 x64.
This is an unsigned preview. Keep a backup before replacing an older installation.

## Updates

The app checks GitHub once at startup. When an update is available,
Settings → About & licenses opens with a prominent notification and update button.
You can also check manually from that page. Installation requires your
confirmation, verifies the download, retains the previous app folder and restarts.
Orders, settings and email credentials stay in the local profile.
Versions 2.0.26–2.0.29 require a manual ZIP replacement to obtain the fixed
Windows update helper in 2.0.30. Close the app and any leftover background instance before replacing application files;
the separate saved-data profile is retained.
[Update and recovery details](breakfast_flutter/docs/UPDATES.md).

## Features

- Read-only IMAP importing, pending-order review and duplicate suppression.
- Exact accommodation matching; no ambiguous number aliases.
- Guest contact and reservation details; saved HTML email previews.
- Categories, menu ordering and availability; compact cabin management.
- Dark mode, backups, and browser/PDF print layouts with a combined timetable and item totals.

## Build and test

Install Flutter 3.47.6 and Visual Studio with Desktop development with C++.
From breakfast_flutter:

```powershell
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
flutter build windows --release --no-pub
```

The release workflow tests and builds Windows, validates the updater helper, and
publishes a release for each new version. Bump both pubspec.yaml and appVersion in
lib/services/updates.dart and update docs/RELEASE-NOTES.md before publishing.

70 automated Flutter tests plus Windows updater process-survival, folder replacement, installation,
checksum rejection, archive traversal rejection and rollback checks. Live mailbox credentials and
physical printers require validation in your own environment.

Third-party notices are in breakfast_flutter/docs/THIRD-PARTY-NOTICES.txt and in
release packages. No application source license has been selected yet.
