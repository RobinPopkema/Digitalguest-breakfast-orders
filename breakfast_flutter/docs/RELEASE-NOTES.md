# Breakfast Orders 2.0.34

- Fixed unstable dragging of expanded menu categories. Dragging now measures the compact row after collapse and keeps the preview attached to the pointer.
- Categories reopen only after the drop animation and placeholder have finished, including drops back in the same position.
- Quick clicks and cancelled drags restore the category without changing menu order.
- Added regression checks for mouse dragging, compact preview size, reopening after drop, cancellation and saved category ordering.
