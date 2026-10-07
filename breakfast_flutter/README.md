# Breakfast Orders 2.0.37 Expressive preview

A separate Windows rebuild of Breakfast Orders 1.22.2 using Flutter 3.47.6,
Dart 3.13.5 and Material 3 Expressive styling. The original Electron source is retained unchanged
in `../Breakfast-Orders-Source`.

## Run

Extract the complete portable Windows ZIP and run `breakfast_orders.exe`.
Windows 10/11 x64 is required. Runtime DLLs are included. Printing uses an
installed Edge, Chrome or Firefox, just as version 1.22.2 did.

Read [START-HERE.txt](docs/START-HERE.txt) before switching from the old app.
This is a preview release: real account authentication and physical printer
output still need a check in the user's environment.

Updating from an earlier Flutter preview reuses the existing Flutter profile and credentials.
The Expressive update uses stock Flutter controls with custom color, typography,
shape and spring-motion treatments; it adds no dependencies. Reduced motion
is respected. Saved-data compatibility and print layouts are preserved.

## Changes in 2.0.37

Moved both import actions to a joined dropdown on Get orders. New order is again
a single manual-entry button. Reimport has previous/next-day arrows around the
date picker; advancing beyond today is disabled.

## Changes in 2.0.36

New order and its submenu now share one joined button with an internal divider,
matching the Print button layout while retaining the primary blue styling.

## Changes in 2.0.35

New order now has Get today's orders and Reimport orders actions. Choose any
past receipt date to reimport one or multiple emails through Pending orders.
Confirmed orders (including merged originals) and pending orders cannot be
imported again. Deleted and dismissed orders can be recovered while their
original email remains in the configured mailbox folder.

## Changes in 2.0.34

Fixed expanded-category dragging: compact drag sizing, stable pointer alignment,
and reopening after the drop animation finishes. Quick clicks and cancellations
restore the category without changing menu order.

## Changes in 2.0.33

Updates now live in About & licenses, with one automatic startup check and a
prominent new-version notice. Adjacent action buttons have consistent spacing.
Dragging a category collapses all categories and reopens the dragged category
on release. Category visibility pauses the whole category while preserving
individual item availability and existing orders.

## Changes in 2.0.28

Fixed the Windows helper launcher and added a process-survival regression check.
The old faulty launcher requires one manual ZIP update. Print summaries now use
portrait pages, category striping and blank timetable cells; split slips include
a footer warning. Settings use compact headers with Save beside Close, and orders
show received/creation timestamps. Existing data and historical quantities remain intact.

## Changes in 2.0.27

GitHub release updates: automatic startup/four-hour checks and a prominent top-menu
Update available button. Downloads are checked against GitHub's SHA-256 asset digest.
The Windows helper verifies the archive, probes startup, waits for the app to close,
keeps a previous-version folder, swaps the application and restarts with the same profile.
Installation is user-confirmed; no email credentials or order data are uploaded.
See [UPDATES.md](docs/UPDATES.md) for release and recovery instructions.

## Changes in 2.0.25

Pending cabin options use normal text; only the current unmatched entry is red.
Edit order uses the same cabin selector as new orders, retaining historical cabin
names as an option. One red toolbar button deletes selected orders or clears all
when nothing is selected, with confirmation.

## Changes in 2.0.24

Reservation numbers are separate guest details, never part of the cabin name.
Existing pending reservation spillover is corrected for display and matching.
Pending cards combine the guest cabin and selector: unmatched entries are red;
matched or manually selected cabins use the normal text color.

## Changes in 2.0.23

Internal cleanup: stable order sorting avoids repeated insertion-position scans;
snapshot updates, menu grouping and email matching use local indexes. Pending
cards reuse their matching result. Print and email previews share browser launching.
Data formats, availability rules, matching ambiguity and print layouts are unchanged.

## Changes in 2.0.22

Menu availability uses plain eye icons matching the delete controls. Menu fields
have consistent padding and spacing, with labels inside fields for clean alignment.

## Changes in 2.0.21

Category headers and selectors are more compact. Square availability controls
show an eye for enabled and a crossed-out eye for disabled, retaining keyboard
activation and accessible toggle state. Availability behavior is unchanged.

## Changes in 2.0.20

Menu rows now show drag handle, category, item name, availability checkbox and delete.
New-entry fields align with existing rows; availability behavior is unchanged.

## Changes in 2.0.19

Settings → Menu has an availability switch for each item. Save all changes applies
it; items stay unavailable until restored. New orders cannot add unavailable items.
Existing orders retain their quantities and print content. Emails requesting an
unavailable item require review and an available replacement; temporary replacements
do not create permanent aliases. Availability persists in saved data and backups;
older data without the field defaults to available. This affects this app only,
not the guest-facing ordering website.

## Changes in 2.0.18

Get orders restarts the automatic-check countdown without enabling paused checks.
Settings combines categories and items under Menu. Category handles move whole
groups, including their children, between other groups. Item handles still move
individual items within or between groups.
Accommodations whitelist is now Cabins: searchable compact pills with edit and
delete controls. Changes remain staged until Save all changes.

## Changes in 2.0.17

Expanded accepted orders follow the configured category and menu item order,
instead of the original imported line order. Historical removed items remain
visible and saved lines and quantities are unchanged.

## Changes in 2.0.16

Full review shows only items that could not be matched automatically, with bold
source names, category pills in the selectors and read-only original quantities.
Automatically matched items remain part of the accepted order.
Menu items are grouped by category. Drag the handles to reorder categories and
items, or move items between categories; Save all changes commits the new order.

## Changes in 2.0.15

New orders select their cabin from the accommodations whitelist. Guest name,
email and phone can be entered on new orders and edited on existing orders.
Guest details remain optional and appear on order cards and print slips.
Existing orders retain support for historical accommodation names.

## Changes in 2.0.14

Email settings uses an interval slider (1 minute to 24 hours). Short intervals
have one-minute steps, longer intervals use 15-minute steps; existing custom
values remain selectable. Use the existing save buttons to apply the interval.
The browser print page displays pages with a Print / Save PDF button. Slips now
include guest name, email and phone; colors and typography match the app.
A4 landscape, the six print modes and measured overflow handling are retained.

## Changes in 2.0.13

Category pills and matching swatches have richer fills and darker text. Category
select labels stay inside the field instead of protruding above the border.
Stored color IDs and print colors are unchanged.

## Changes in 2.0.12

New categories default to unused colors, then rotate through the least-used
colors when the palette is full. Color swatches match pill backgrounds.

## Changes in 2.0.11

Pending-order warning pills follow the customer information on the same line,
wrapping naturally in smaller windows.

## Changes in 2.0.10

Shared blue accents now coordinate with the blue background and icon. Standard
buttons and icon actions share a 44-pixel height. Get orders no longer shows the
last-update time; its subtle countdown remains. Settings has an immediate Dark
mode switch, saved between launches in appearance-settings.json in the Flutter
profile. Category colors and white print layouts remain unchanged. Appearance
is local to this profile and is not included in the order-data backup.

## Changes in 2.0.9

Incoming orders are now labelled Pending orders. Their cards match accepted orders:
white bordered surfaces, delivery-time badges, contact icons, total item quantities,
red Comment pills and structured expanded item rows. Cabin selection, fault pills,
review, acceptance and dismissal remain available.

## Changes in 2.0.8

Incoming and accepted orders share a centered column capped at 1040 logical pixels,
matching the Settings modal width. Smaller windows retain responsive side margins.

## Changes in 2.0.7

- The header now uses the same egg-and-plate artwork as the Windows icon. App
  colors follow its blue/navy and warm yellow palette; stored category colors
  and print layouts remain unchanged.
- Category colors are circular swatches before the name with a 24-color flyout.
  New-entry and existing-entry text fields have identical widths. Menu-item
  category selectors use colored backgrounds, dots and bold names.
- Order cards have clearer headings, delivery-time badges, contact icons and
  structured item/quantity rows. A red Comment pill sits before Edit and opens
  the comment. Expanded cards do not repeat contact information.
- A small muted countdown ring now sits inside the right side of Get orders,
  replacing the filled pie. Hover still shows the exact remaining time.

## Changes in 2.0.6

Settings opens one modal with left-side navigation: Categories, Menu items,
Accommodations whitelist, Email, Backup & restore, and About & licenses.
All sections display directly in its right panel. Switching sections retains menu
and email drafts. Save all changes commits the menu/whitelist batch; email has its
own connection/save controls. Closing discards unsaved menu edits and clears the
entered email password. Restore confirms replacement and closes the stale draft.

## Changes in 2.0.5

The top toolbar now groups Get orders, Print, Settings, Clear all orders and New
order. Settings contains Manage menu, a Backup and restore submenu, Email settings,
and About and licenses. Clear all orders is red and confirms the full order count,
even when only some orders are selected. Delete selected remains by the order list.

Print is a split button: the main button prints all printouts; its arrow offers
Orders only (or Print (x) orders when selected), Delivery schedule, Items overview,
and Timetable. The print rendering and saved-data formats are unchanged.

## Changes in 2.0.4

Get orders is now a full button with the last successful check time beneath its
label. A pie on its right shrinks as the next scheduled automatic update nears.
Hover over it for the remaining minutes and seconds. Paused automatic updates
show a pause icon. The countdown uses the service's actual periodic schedule;
manual checks do not reset it. Long-running checks never overlap.

## Changes in 2.0.3

The header has a refresh icon and last successful update time beside Manage menu.
Click the icon to check for incoming orders. It shows progress during a check and
an error indicator if the update fails; a failed check does not advance the time.
Before the first successful check of this session the time is shown as a dash.
The large mail panel is removed. Email settings remain under More; clicking
refresh also opens setup if no account is configured. Automatic checks continue
with the existing settings.

## Changes in 2.0.2

- Manage menu has a blank entry row for categories, items and cabins. Press Enter
  to add each entry; the field clears, retains focus and keeps the selected category.
  Save all changes commits the batch; Cancel discards it.
- Incoming orders use compact rows with fault pills and actions on the right.
- Guest name, email and phone are extracted from the guest section and retained
  on acceptance and later edits. Expand an order to select/copy full contact details.
- A unique direct cabin match is preselected, ignoring case and outer spaces.
  Ambiguous or missing matches still require selection; acceptance remains explicit.
  Cabin aliases are never learned: choosing Panorama 1 for a guest entry of 1
  does not match future entries of 1. Remembered aliases apply only to menu items.
- The UI now says Select cabin. The saved `safeCabins` keys remain compatible.
- Show email opens saved HTML in Edge, Chrome or Firefox with layout/styles intact.
  Active content, links and remote resources/images are blocked. Old queued emails
  fall back to saved text; contacts are recovered from that text where available.
  Older accepted orders without saved guest/source data cannot recover those details.
  New accepted orders retain the source email for Show email, including in backups.

## Features

- Native Flutter Material 3 Expressive desktop UI, compact order rows, single-row expansion,
  select all / partial selection, deletion, six sorting modes and saved preference.
- Manual orders with seven breakfast slots, searchable categorized quantities,
  keyboard focus handling, comments, retained removed-item snapshots and metadata.
- Menu and category management, batch editing, 24 original category colors,
  updates to existing order snapshots, and a managed cabin list.
- DigitalGuest MIME parsing, read-only TLS IMAP folder listing/checking,
  local-today receipt dates, rollover, sender validation, dinner exclusion,
  review for ambiguity, SEARCH fallbacks, metadata-only compatibility scans,
  limits, duplicate suppression and durable pending imports.
- Quick approval when mapped, full revision otherwise, remembered aliases,
  cabin validation, source text, comments and original guest-cabin metadata.
- Windows DPAPI credential encryption, native JSON file dialogs and single-instance
  behavior for the default profile. No Node or Electron sidecar is shipped.
- Six print modes using the original renderer, CSS and measured pagination.

## Data compatibility and rollback

First launch copies `%APPDATA%\Breakfast Orders` into
`%APPDATA%\Breakfast Orders Flutter`. Close Electron before the initial copy.
The original profile is never modified. Subsequent launches use the Flutter
profile and do not repeat migration. Existing JSON fields and unknown metadata
are preserved; old backups without `safeCabins` are accepted without trusting
legacy `rooms`. Email duplicate keys retain the original account hashing format.

The old encrypted mail password is not copied. Enter it again; it is then
protected by the current Windows account using DPAPI. Automatic checks start
paused after migration. The new settings use `flutterSecret`; these settings
are not exported in data backups or shared with the old app.

Writes use flushed temporary files and Windows atomic replacement, previous-file
`.bak` copies, and up to 30 UTC-dated daily order backups. Invalid saves are
rejected; corrupt primary order files fall back to a valid `.bak`.

Exports retain `format: breakfast-orders-backup`, `version: 1` and the original
`data` object. Accepted orders and menu changes can therefore be restored in
1.22.2. Pending imports and credentials are separate; full recovery needs a copy
of the closed Flutter profile. Avoid enabling both apps' importers simultaneously.

For isolated development, pass `--profile=C:\path\to\test-profile` to the EXE.
That option disables automatic copying from the user's existing profile.

## Architecture

- `lib/model.dart`: JSON compatibility, palette, order snapshots and sorting.
- `lib/services/store.dart`: profile copy, locks, backups, validation and atomic saves.
- `lib/services/email_parser.dart`: MIME / DigitalGuest parsing and stable identifiers.
- `lib/services/mail_transport.dart`: enough_mail adapter; EXAMINE and BODY.PEEK only.
- `lib/services/email_service.dart`: schedule, filtering, review queue, mappings,
  deduplication and save-before-dismiss acceptance recovery.
- `lib/services/printing.dart`: escaped data embedded in standalone print HTML.
- `assets/print`: renderer/CSS adapted from 1.22.2, with guest details, refreshed colors and unchanged pagination code.
- `windows/runner/breakfast_native.cpp`: Windows DPAPI and open/save dialogs.
- `lib/ui/expressive_theme.dart`: coordinated colors, shape transitions and reduced-motion support.
- `lib/ui`: Material 3 Expressive order list, editors, menu management and mail settings/review.

The print renderer is intentionally retained in JavaScript, executed by the
external browser. The application UI and email backend run in Flutter/Dart.
This protects print-layout compatibility without packaging Chromium or Node.

## Build and test

Install Flutter and Visual Studio Build Tools with Desktop development with C++.
Set `FLUTTER_ROOT` to the SDK path when using `tool/flutter.ps1`; its fallback is
the SDK already present on this development machine.

From the workspace root:

```powershell
& ./breakfast_flutter/tool/flutter.ps1 pub get
& ./breakfast_flutter/tool/flutter.ps1 analyze --no-pub
& ./breakfast_flutter/tool/flutter.ps1 test --no-pub
& ./breakfast_flutter/tool/flutter.ps1 build windows --release --no-pub
& ./breakfast_flutter/tool/package.ps1
```

Or run normal `flutter pub get`, `flutter test`, and `flutter build windows
--release` from this directory. `pubspec.lock` pins the resolved dependencies.

## Validation

The unmodified original suite passed 28/28 before implementation. The Flutter suite passes 60 tests covering
MIME parsing, date handling, migration, recovery, data compatibility, review,
interrupted acceptance, real IMAP protocol behavior and UI workflows.

```powershell
& ./breakfast_flutter/tool/flutter.ps1 test --no-pub test/visual_test.dart --dart-define=CAPTURE_PREVIEWS=true
node breakfast_flutter/tool/verify-print.cjs
```

The visual test exports anonymous screen and print fixtures to `docs/previews`.
The print harness uses Playwright/Chrome and the original app's jsdom dependency;
set `PLAYWRIGHT_PATH` and `CHROME_PATH` for another development environment. It
compares order content and summaries with 1.22.2 for all six modes plus oversized
orders/comments, checking for overflow. Results are in `docs/print-verification.json`.

The EXE accepts `--smoke-test=C:\path\to\report.json` to test native DPAPI and
print generation, then exit without opening any user profile. The report from
this build is in `docs/native-smoke.json`. This mode uses only a fixed test string.

No live mailbox or physical printer was used in development. The local protocol
suite covers the actual Dart client, including rejected SEARCH and metadata reads.

## Packaging and licenses

`tool/package.ps1` creates a portable ZIP, includes the required Visual C++ runtime
DLLs, Flutter/Dart notices, and unmodified enough_mail library source under MPL 2.0.
It writes measured compressed/uncompressed sizes and a SHA-256 checksum to
`../release/package-size.json`. The release is unsigned.










