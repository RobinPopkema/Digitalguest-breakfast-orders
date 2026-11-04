# Breakfast Orders 2.0.42

- Unknown items in full review can be mapped to an existing product or added as a new menu item.
- New menu items can use an existing category or a new category created directly in the dialog, with an automatically selected color.
- Saving selects the new product for the order and preserves the guest's quantity. The order stays pending until accepted.
- Full review allows remapping every item, including automatic matches.
- Oat Milk is not automatically matched to Milk; explicit saved manual mappings still apply.
- Verified with 92 Flutter tests, including creation, cancellation, persistence and order acceptance.
