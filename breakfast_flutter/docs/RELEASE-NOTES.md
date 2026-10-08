# Breakfast Orders 2.0.38

- Added checkboxes and select-all to Pending orders, independent of confirmed-order selection.
- Added Dismiss selected, with confirmation. Email messages and import history stay intact; dismissed orders can still be explicitly reimported.
- Added Accept all ready and Accept selected ready. Only orders without source warnings, with matched available menu items, valid quantities and delivery times, and a matched or explicitly reviewed cabin are approved.
- Orders needing review stay pending. Bulk approval retains existing duplicate protection and saves each accepted order before removing it from the pending queue.
