# Updates and releases

Public release source: https://github.com/RobinPopkema/Digitalguest-breakfast-orders
The app checks the latest non-draft, non-prerelease release on startup and every four
hours. About & licenses also has a manual check. Only a higher numeric x.y.z version
with a Windows ZIP and a GitHub SHA-256 digest is offered. API rate limits and offline
failures leave the app usable; details appear on the About page.

Click Update available in the top bar, review the release notes and confirm.
The helper verifies the hash and archive paths, performs a native startup probe,
stages files beside the installation, then waits for the existing app to exit.
Order data and protected credentials remain in the separate profile directory.
The install folder must be writable; linked folders and profiles inside the app
folder are rejected. There is no elevation prompt or unattended installation.

A sibling .breakfast-previous-* folder is retained for recovery. Close the app before
manually restoring that folder. Diagnostic logs and the downloaded archive are in
%TEMP%/Breakfast-Orders-Update-*. A failed swap/restart launch restores the old folder.
The helper validates startup but cannot guarantee every future runtime operation.

Versions 2.0.26–2.0.29 need a manual ZIP replacement to obtain the fixed helper
in 2.0.30. Close the app and any leftover breakfast_orders.exe background instance
before replacing application files; the separate profile is retained. The launcher
uses a hidden PowerShell process with its working directory outside the installation.
The helper also resets its PowerShell and native working directories. Restart and
failure recovery open the app visibly. Regression checks launch from the installation
directory and verify folder replacement after application exit.

Publishing: bump both pubspec.yaml and appVersion in lib/services/updates.dart,
update RELEASE-NOTES.md, then push main. The Windows release workflow tests, builds,
checks the helper and creates vX.Y.Z once; it never overwrites an existing release.
GitHub computes the asset digest after upload. Keep repository write access restricted.
The app's digest check detects corrupt downloads; it is not a code-signing certificate.
