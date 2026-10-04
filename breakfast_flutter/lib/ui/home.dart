import 'package:flutter/material.dart';

import '../controller.dart';
import '../model.dart';
import '../services/printing.dart';
import '../services/email_parser.dart';
import 'common.dart';
import 'email_dialogs.dart';
import 'manage.dart';
import 'order_editor.dart';
import 'expressive_theme.dart';
import 'update_countdown.dart';

class HomePage extends StatefulWidget {
  const HomePage(this.app, {super.key});
  final AppController app;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final selected = <String>{}, cabins = <String, String>{};
  String? expanded, expandedEmail;
  bool printing = false;
  AppController get app => widget.app;
  @override
  void initState() {
    super.initState();
    app.addListener(update);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (app.store.migrationNotice != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(app.store.migrationNotice!),
            duration: const Duration(seconds: 15),
            showCloseIcon: true,
          ),
        );
      }
    });
  }

  void update() {
    if (mounted) {
      setState(() {
        selected.removeWhere((id) => findById(app.data['orders'], id) == null);
      });
    }
  }

  @override
  void dispose() {
    app.removeListener(update);
    super.dispose();
  }

  Future<void> run(Future<void> Function() task) async {
    try {
      await task();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> installUpdate() async {
    final release = app.updates.available;
    if (release == null || app.updates.installing) return;
    if (!await confirm(
      context,
      'Update to ${release['version']}?',
      'The app will download the update and restart. Your orders and settings are kept.\n\n${release['notes']}',
      action: 'Update and restart',
    )) {
      return;
    }
    await run(() => app.updates.install(app.store.directory.path));
  }

  void settings() => showDialog(
    context: context,
    builder: (_) => ManageDialog(app, initialSection: 2),
  );

  Future<void> refreshOrders() async {
    if (!app.email.configured) {
      settings();
      return;
    }
    await run(() async {
      await app.email.check(resetTimer: true);
      if (mounted && app.email.error) {
        showError(
          context,
          'Update failed. Check your connection or settings under Settings.',
        );
      }
    });
  }

  Widget updateControl() {
    final mail = app.email;
    return Row(
      key: const ValueKey('update-control'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: mail.busy
              ? 'Updating…'
              : mail.error
              ? 'Update failed — retry'
              : 'Get orders',
          child: FilledButton.tonalIcon(
            onPressed: mail.busy ? null : refreshOrders,
            icon: mail.busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      semanticsLabel: 'Updating',
                    ),
                  )
                : Icon(
                    mail.error
                        ? Icons.sync_problem_outlined
                        : Icons.refresh_rounded,
                    color: mail.error
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Get orders'),
                const SizedBox(width: 12),
                UpdateCountdown(mail),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void edit([Json? order]) => showDialog(
    context: context,
    builder: (_) => OrderEditor(app, order: order),
  );

  Widget settingsControl() => OutlinedButton.icon(
    onPressed: () =>
        showDialog(context: context, builder: (_) => ManageDialog(app)),
    icon: const Icon(Icons.settings_outlined, size: 18),
    label: const Text('Settings'),
  );
  Widget printControl() {
    final enabled = !printing && rows(app.data['orders']).isNotEmpty;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton.icon(
            onPressed: enabled ? () => print('all') : null,
            icon: Icon(
              printing ? Icons.hourglass_top : Icons.print_outlined,
              size: 18,
            ),
            label: const Text('Print'),
          ),
          SizedBox(
            height: 24,
            child: VerticalDivider(
              width: 1,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Print options',
            style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
            enabled: enabled,
            onSelected: print,
            icon: const Icon(Icons.arrow_drop_down),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: selected.isEmpty ? 'orders' : 'selected',
                child: Text(
                  selected.isEmpty
                      ? 'Orders only'
                      : 'Print (${selected.length}) orders',
                ),
              ),
              const PopupMenuItem(
                value: 'schedule',
                child: Text('Delivery schedule'),
              ),
              const PopupMenuItem(
                value: 'totals',
                child: Text('Items overview'),
              ),
              const PopupMenuItem(value: 'timetable', child: Text('Timetable')),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> print(String mode) async {
    setState(() => printing = true);
    await run(() => Printing.print(app.data, mode, selected));
    if (mounted) setState(() => printing = false);
  }

  Future<void> deleteOrders() async {
    final all = selected.isEmpty;
    final count = all ? app.data['orders'].length : selected.length;
    if (count == 0) return;
    if (await confirm(
      context,
      'Delete $count orders?',
      all
          ? 'This deletes all accepted orders. Back up your data first if you may need it later.'
          : 'This deletes the selected accepted orders.',
    )) {
      await run(() async {
        app.edit((data) {
          if (all) {
            data['orders'] = <Json>[];
          } else {
            data['orders'].removeWhere((o) => selected.contains(o['id']));
          }
        });
        selected.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = app.data, orders = sortedOrders(data), mail = app.email;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 24, 18),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 32,
                runSpacing: 12,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/icon-256.png',
                        width: 52,
                        height: 52,
                        semanticLabel: 'Breakfast Orders',
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Breakfast orders',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            'Plan the morning, one cabin at a time.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      updateControl(),
                      printControl(),
                      if (app.updates.available != null)
                        FilledButton.icon(
                          onPressed: app.updates.installing
                              ? null
                              : installUpdate,
                          icon: const Icon(Icons.system_update_alt),
                          label: Text(
                            app.updates.installing
                                ? 'Downloading ${(app.updates.progress * 100).round()}%'
                                : 'Update available',
                          ),
                        ),
                      settingsControl(),
                      OutlinedButton.icon(
                        onPressed: orders.isEmpty ? null : deleteOrders,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.error,
                          side: BorderSide(
                            color: orders.isEmpty
                                ? Theme.of(context).colorScheme.outlineVariant
                                : Theme.of(context).colorScheme.error,
                          ),
                        ),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: Text(
                          selected.isEmpty
                              ? 'Clear all orders'
                              : 'Delete selected (${selected.length})',
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: () => edit(),
                        icon: const Icon(Icons.add),
                        label: const Text('New order'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: settingsContentWidth + 56,
                  ),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(28, 20, 28, 24),
                    children: [
                      if (mail.queue.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Text(
                          'Pending orders · ${mail.queue.length}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 10),
                        for (final entry in mail.queue) emailRow(entry),
                        const SizedBox(height: 20),
                      ],
                      const SizedBox(height: 12),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        runSpacing: 8,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Checkbox(
                                tristate: true,
                                value: selected.isEmpty
                                    ? false
                                    : selected.length == orders.length
                                    ? true
                                    : null,
                                onChanged: orders.isEmpty
                                    ? null
                                    : (_) => setState(() {
                                        if (selected.length == orders.length) {
                                          selected.clear();
                                        } else {
                                          selected.addAll(
                                            orders.map(
                                              (o) => o['id'] as String,
                                            ),
                                          );
                                        }
                                      }),
                              ),
                              Text(
                                'Orders · ${orders.length}',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              PopupMenuButton<String>(
                                tooltip: 'Sort orders',
                                initialValue: data['viewSort'] ?? 'room',
                                onSelected: (mode) => run(() async {
                                  app.edit((d) => d['viewSort'] = mode);
                                }),
                                icon: const Icon(Icons.sort),
                                itemBuilder: (_) =>
                                    {
                                          'room': 'Room number',
                                          'room-desc': 'Room descending',
                                          'delivery': 'Delivery time',
                                          'delivery-desc': 'Latest delivery',
                                          'newest': 'Newest received',
                                          'oldest': 'Oldest received',
                                        }.entries
                                        .map(
                                          (e) => CheckedPopupMenuItem(
                                            value: e.key,
                                            checked: data['viewSort'] == e.key,
                                            child: Text(e.value),
                                          ),
                                        )
                                        .toList(),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (orders.isEmpty)
                        Card(
                          elevation: 0,
                          child: Padding(
                            padding: const EdgeInsets.all(48),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.breakfast_dining_outlined,
                                  size: 48,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Ready for a new morning',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Add menu items in Settings, then create your first breakfast order.',
                                ),
                                const SizedBox(height: 20),
                                FilledButton.icon(
                                  onPressed: () => edit(),
                                  icon: const Icon(Icons.add),
                                  label: const Text('New order'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      for (final order in orders) orderRow(order),
                      const SizedBox(height: 20),
                      Text(
                        'Saved automatically on this computer',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget orderRow(Json order) {
    final open = expanded == order['id'];
    final qty = rows(order['lines'])
        .fold<num>(0, (sum, l) => sum + (l['qty'] as num));
    final colors = Theme.of(context).colorScheme;
    final comment = '${order['comment'] ?? ''}';
    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : expressiveDuration,
      curve: const ExpressiveSpring(),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: selected.contains(order['id'])
            ? colors.primaryContainer.withValues(alpha: .45)
            : colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected.contains(order['id'])
              ? colors.primary
              : colors.outlineVariant,
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 8, 10),
            child: Row(
              children: [
                Checkbox(
                  value: selected.contains(order['id']),
                  onChanged: (v) => setState(() {
                    if (v!) {
                      selected.add(order['id']);
                    } else {
                      selected.remove(order['id']);
                    }
                  }),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 14,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            order['room'],
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: colors.onSurface,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: colors.primaryContainer.withValues(
                                alpha: .65,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.schedule,
                                  size: 15,
                                  color: colors.primary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '${order['slot'] ?? ''}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: colors.onPrimaryContainer,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '$qty items',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      GuestContact(order),
                    ],
                  ),
                ),
                if (comment.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Tooltip(
                      message: comment,
                      child: ActionChip(
                        label: const Text('Comment'),
                        labelStyle: TextStyle(
                          color: colors.error,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                        backgroundColor: colors.errorContainer,
                        side: BorderSide.none,
                        onPressed: () => setState(
                          () => expanded = open ? null : order['id'],
                        ),
                      ),
                    ),
                  ),
                IconButton.filledTonal(
                  tooltip: 'Edit order for ${order['room']}',
                  onPressed: () => edit(order),
                  icon: const Icon(Icons.edit_outlined, size: 20),
                ),
                IconButton(
                  tooltip:
                      '${open ? 'Collapse' : 'Expand'} order ${order['room']}',
                  onPressed: () =>
                      setState(() => expanded = open ? null : order['id']),
                  icon: Icon(open ? Icons.expand_less : Icons.expand_more),
                ),
              ],
            ),
          ),
          ExpressiveSize(
            child: open
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(48, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Divider(height: 20),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'ORDER ITEMS',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: .8,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              Text(
                                'QTY',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        for (final line in orderedOrderLines(app.data, order))
                          Container(
                            margin: const EdgeInsets.only(bottom: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: colors.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Wrap(
                                    spacing: 10,
                                    runSpacing: 6,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      CategoryBadge(
                                        findById(
                                              app.data['categories'],
                                              line['categoryId'],
                                            ) ??
                                            {
                                              'name': line['categoryName'],
                                              'color': line['categoryColor'],
                                            },
                                      ),
                                      Text(
                                        line['name'],
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  '${line['qty']}',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: colors.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (comment.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: colors.errorContainer.withValues(
                                alpha: .4,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: SelectableText(
                              comment,
                              style: TextStyle(
                                color: colors.error,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        if (order['emailSource'] is Json &&
                            (order['emailSource']['html'] != null ||
                                order['emailSource']['text'] != null))
                          Align(
                            alignment: Alignment.centerRight,
                            child: ShowEmailButton(order['emailSource']),
                          ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity, height: 0),
          ),
        ],
      ),
    );
  }

  Widget emailRow(Json entry) {
    final ids = app.email.matches(entry);
    final quick = app.email.quickReady(entry, matchedIds: ids);
    final safe = rows(app.data['safeCabins']);
    final chosen = safe.any((c) => c['id'] == cabins[entry['id']])
        ? cabins[entry['id']]
        : app.email.matchingCabin(entry);
    final open = expandedEmail == entry['id'];
    final colors = Theme.of(context).colorScheme;
    final comment = '${entry['comment'] ?? ''}';
    final qty = rows(entry['lines'])
        .fold<num>(0, (sum, l) => sum + (l['qty'] as num));
    final missing = ids.where((id) => id.isEmpty).length;
    final faults = <String>[
      if (chosen == null) 'Select cabin',
      if (!slots.contains(entry['slot'])) 'Delivery time',
      if (missing > 0) '$missing unmapped',
      if (ids.isEmpty) 'No items',
      if (entry['kind'] != 'breakfast') 'Check breakfast',
      if ((entry['warnings'] as List? ?? []).isNotEmpty) 'Source warning',
    ];
    void review() => showDialog(
      context: context,
      builder: (_) => EmailReview(app, entry, selectedCabin: chosen),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 14,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: 200,
                            child: DropdownButtonFormField<String>(
                              key: ValueKey('cabin-${entry['id']}-$chosen'),
                              initialValue: chosen,
                              isExpanded: true,
                              style: TextStyle(
                                fontFamily: 'Segoe UI',
                                color: chosen == null
                                    ? colors.error
                                    : colors.onSurface,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                              hint: Text(
                                guestCabin(entry).isEmpty
                                    ? 'Select cabin'
                                    : guestCabin(entry),
                                style: TextStyle(color: colors.error),
                              ),
                              selectedItemBuilder: (_) => safe
                                  .map(
                                    (c) => Text(
                                      cabins[entry['id']] == null
                                          ? guestCabin(entry)
                                          : c['name'],
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  )
                                  .toList(),
                              decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                              ),
                              items: safe
                                  .map(
                                    (c) => DropdownMenuItem(
                                      value: c['id'] as String,
                                      child: Text(
                                        c['name'],
                                        style: TextStyle(
                                          color: colors.onSurface,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => cabins[entry['id']] = v!),
                            ),
                          ),
                          if ('${entry['slot'] ?? ''}'.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: colors.primaryContainer.withValues(
                                  alpha: .65,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.schedule,
                                    size: 15,
                                    color: colors.primary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${entry['slot']}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: colors.onPrimaryContainer,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Text(
                            '$qty items',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      GuestContact(
                        entry,
                        trailing: [
                          for (final fault in faults)
                            Tooltip(
                              message: fault == 'Source warning'
                                  ? (entry['warnings'] as List).join('\n')
                                  : fault,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.errorContainer,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  fault,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: colors.onErrorContainer,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (comment.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Tooltip(
                      message: comment,
                      child: ActionChip(
                        label: const Text('Comment'),
                        labelStyle: TextStyle(
                          color: colors.error,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                        backgroundColor: colors.errorContainer,
                        side: BorderSide.none,
                        onPressed: () => setState(
                          () => expandedEmail = open ? null : entry['id'],
                        ),
                      ),
                    ),
                  ),
                IconButton.filledTonal(
                  tooltip: quick ? 'Accept breakfast order' : 'Review & map',
                  onPressed: quick && chosen == null
                      ? null
                      : () {
                          if (quick) {
                            run(() async {
                              app.email.accept({
                                'id': entry['id'],
                                'safeCabinId': chosen,
                                'confirmed': true,
                                'mode': 'quick',
                              });
                            });
                          } else {
                            review();
                          }
                        },
                  icon: Icon(
                    quick ? Icons.check_circle_outline : Icons.edit_outlined,
                    size: 20,
                  ),
                ),
                IconButton(
                  tooltip:
                      '${open ? 'Collapse' : 'Expand'} pending order ${entry['room']}',
                  onPressed: () =>
                      setState(() => expandedEmail = open ? null : entry['id']),
                  icon: Icon(open ? Icons.expand_less : Icons.expand_more),
                ),
              ],
            ),
          ),
          ExpressiveSize(
            child: open
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Divider(height: 20),
                        for (final warning in entry['warnings'] ?? [])
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              '$warning',
                              style: TextStyle(color: colors.error),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'ORDER ITEMS',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: .8,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              Text(
                                'QTY',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        for (var i = 0; i < ids.length; i++)
                          Builder(
                            builder: (_) {
                              final line = entry['lines'][i],
                                  item = findById(app.data['items'], ids[i]),
                                  category = findById(
                                    app.data['categories'],
                                    item?['categoryId'],
                                  );
                              return Container(
                                margin: const EdgeInsets.only(bottom: 4),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Wrap(
                                            spacing: 10,
                                            runSpacing: 6,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            children: [
                                              if (category != null)
                                                CategoryBadge(category)
                                              else
                                                Icon(
                                                  Icons.warning_amber,
                                                  color: colors.error,
                                                  size: 18,
                                                ),
                                              Text(
                                                '${item?['name'] ?? line['name']}',
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (item == null)
                                            Text(
                                              'Needs mapping',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: colors.error,
                                              ),
                                            )
                                          else if (item['name'] != line['name'])
                                            Text(
                                              'Email: ${line['name']}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: colors.onSurfaceVariant,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      '${line['qty']}',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: colors.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        if (comment.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: colors.errorContainer.withValues(
                                alpha: .4,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: SelectableText(
                              comment,
                              style: TextStyle(
                                color: colors.error,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 8,
                          children: [
                            ShowEmailButton(entry),
                            TextButton(
                              onPressed: review,
                              child: const Text('Full review'),
                            ),
                            TextButton(
                              onPressed: () async {
                                if (await confirm(
                                  context,
                                  'Dismiss pending order?',
                                  'The email stays untouched and will not be imported again.',
                                  action: 'Dismiss',
                                )) {
                                  run(() async {
                                    app.email.dismiss(entry['id']);
                                  });
                                }
                              },
                              child: const Text('Dismiss'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity, height: 0),
          ),
        ],
      ),
    );
  }
}
