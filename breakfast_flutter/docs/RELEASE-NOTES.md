Breakfast Orders 2.0.30

- Fixed the updater holding its own installation folder open. Both the launcher and PowerShell helper switch to the temporary update folder before replacement.
- Successful updates and failure recovery reopen the app visibly instead of creating a hidden background instance.
- Added regression checks that launch from the installation folder and verify it can be renamed after app exit.
- Pending and confirmed orders, and PDF delivery slips, follow the configured category and item order. Historical removed items and quantities are retained.
- Delivery-slip headers show only cabin and delivery time. Guest contact details, reservation numbers and received/creation timestamps remain in the app, not on slips.

Updating from 2.0.26–2.0.29: close the app and any leftover breakfast_orders.exe background instance, then extract the complete Windows ZIP and run breakfast_orders.exe. These older builds contain the faulty updater and need manual replacement. Your saved profile remains in its separate AppData folder.
