import 'package:flutter/material.dart';

import '../model.dart';
import '../services/email_parser.dart';
import '../services/email_preview.dart';

const settingsContentWidth = 1040.0;

// Richer screen colors retain the stored palette IDs and original print colors.
Color categoryFill(int index) => Color.lerp(
  Color(palette[index % palette.length][0]),
  Color(palette[index % palette.length][1]),
  .14,
)!;
Color categoryInk(int index) =>
    Color.lerp(Color(palette[index % palette.length][1]), Colors.black, .18)!;

class GuestContact extends StatelessWidget {
  const GuestContact(
    this.entry, {
    super.key,
    this.compact = false,
    this.trailing = const [],
  });
  final Json entry;
  final bool compact;
  final List<Widget> trailing;
  @override
  Widget build(BuildContext context) {
    final guest = {...guestDetails(entry)};
    final date = orderDateLabel(entry);
    if (date.isNotEmpty) guest['date'] = date;
    const icons = {
      'date': Icons.event_outlined,
      'name': Icons.person_outline,
      'email': Icons.alternate_email,
      'phone': Icons.phone_outlined,
      'reservation': Icons.confirmation_number_outlined,
    };
    final keys = icons.keys
        .where((key) => '${guest[key] ?? ''}'.isNotEmpty)
        .toList();
    if (keys.isEmpty && trailing.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Wrap(
        spacing: 18,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final key in keys)
            Tooltip(
              message:
                  '${key == 'reservation' ? 'Reservation: ' : ''}${guest[key]}',
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icons[key],
                      size: 15,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: compact
                          ? Text(
                              '${guest[key]}',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            )
                          : SelectableText(
                              '${guest[key]}',
                              style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ...trailing,
        ],
      ),
    );
  }
}

class ShowEmailButton extends StatelessWidget {
  const ShowEmailButton(this.entry, {super.key});
  final Json entry;
  @override
  Widget build(BuildContext context) => TextButton.icon(
    icon: const Icon(Icons.open_in_browser, size: 18),
    label: const Text('Show email'),
    onPressed: () async {
      try {
        await EmailPreview.show(entry);
      } catch (e) {
        if (context.mounted) showError(context, e);
      }
    },
  );
}

void showError(BuildContext context, Object error) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$error'),
        duration: const Duration(seconds: 8),
        showCloseIcon: true,
      ),
    );
Future<bool> confirm(
  BuildContext context,
  String title,
  String message, {
  String action = 'Delete',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

class CategoryBadge extends StatelessWidget {
  const CategoryBadge(this.category, {super.key});
  final Json category;
  @override
  Widget build(BuildContext context) {
    final index = ((category['color'] ?? 0) as num).toInt() % palette.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: categoryFill(index),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '${category['name'] ?? 'Removed category'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: categoryInk(index),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class EditorDialog extends StatelessWidget {
  const EditorDialog({
    super.key,
    required this.title,
    required this.body,
    this.actions = const [],
    this.headerActions = const [],
    this.width = 780,
  });
  final String title;
  final Widget body;
  final List<Widget> actions;
  final List<Widget> headerActions;
  final double width;
  @override
  Widget build(BuildContext context) => Dialog(
    clipBehavior: Clip.antiAlias,
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: width,
        maxHeight: MediaQuery.sizeOf(context).height - 64,
      ),
      child: SizedBox(
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              color: Theme.of(context).colorScheme.primaryContainer,
              padding: const EdgeInsets.fromLTRB(20, 6, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  ...headerActions,
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(child: body),
            if (actions.isNotEmpty) const Divider(height: 1),
            if (actions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: actions,
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    super.key,
    required this.name,
    required this.value,
    required this.onChange,
    this.canIncrease = true,
  });
  final String name;
  final int value;
  final ValueChanged<int> onChange;
  final bool canIncrease;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: value > 0 ? colors.secondaryContainer : colors.surfaceContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Remove one $name',
            onPressed: () => onChange(-1),
            icon: const Icon(Icons.remove_rounded, size: 20),
          ),
          SizedBox(
            width: 34,
            child: Semantics(
              liveRegion: true,
              label: '$value $name',
              excludeSemantics: true,
              child: Text(
                '$value',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: colors.onSecondaryContainer,
                ),
              ),
            ),
          ),
          IconButton.filled(
            style: IconButton.styleFrom(
              foregroundColor: colors.onPrimary,
              backgroundColor: colors.primary,
            ),
            tooltip: 'Add one $name',
            onPressed: canIncrease ? () => onChange(1) : null,
            icon: const Icon(Icons.add_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}
