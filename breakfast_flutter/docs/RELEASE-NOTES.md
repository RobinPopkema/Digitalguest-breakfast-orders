# Breakfast Orders 2.0.35

- Added two actions under New order: Get today’s orders and Reimport orders.
- Get today’s orders reads all breakfast orders received today, including previously imported orders that have since been deleted.
- Reimport orders lets you choose a receipt date, including an earlier day, and select one or multiple emails.
- Existing confirmed orders, originals inside merged orders, and pending orders are blocked from duplicate import.
- Recovered orders enter Pending orders for the normal matching and review flow, preserving quantities, guest details and original receipt dates.
- Recovery reads the configured mailbox folder without marking messages read or changing them. The original email must still be present there.
- Includes the expanded-category drag fix from 2.0.34.
