import 'package:flutter/material.dart';

import '../model.dart';
import '../services/email_service.dart';
import '../services/email_parser.dart';
import 'common.dart';

class ReimportOrders extends StatefulWidget {
  const ReimportOrders(this.email, {super.key});
  final EmailService email;
  @override
  State<ReimportOrders> createState() => _ReimportOrdersState();
}

class _ReimportOrdersState extends State<ReimportOrders> {
  late DateTime day;
  List<Json> candidates = [];
  final selected = <String>{};
  bool loading = false;
  String? error;

  @override
  void initState() {
    super.initState();
    day = widget.email.now();
    widget.email.addListener(refresh);
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  @override
  void dispose() {
    widget.email.removeListener(refresh);
    super.dispose();
  }

  void refresh() {
    if (!mounted) return;
    setState(() {
      selected.removeWhere(
        (key) => widget.email.importBlockReason(key) != null,
      );
    });
  }

  Future<void> load() async {
    if (!mounted) return;
    setState(() {
      loading = true;
      error = null;
      selected.clear();
      candidates = [];
    });
    try {
      final result = await widget.email.reimportCandidates(day);
      if (mounted) setState(() => candidates = result);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> chooseDay() async {
    final date = await showDatePicker(
      context: context,
      initialDate: day,
      firstDate: DateTime(2000),
      lastDate: widget.email.now(),
      helpText: 'Choose the day the email arrived',
    );
    if (date == null || !mounted) return;
    setState(() => day = date);
    await load();
  }

  void import() {
    try {
      final count = widget.email.reimportSelected(
        candidates.where((entry) => selected.contains(entry['key'])).toList(),
      );
      Navigator.pop(context, count);
    } catch (e) {
      setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final available = candidates
        .where((entry) => widget.email.importBlockReason(entry['key']) == null)
        .toList();
    final working = loading || widget.email.busy;
    return EditorDialog(
      title: 'Reimport orders',
      width: settingsContentWidth,
      headerActions: [
        FilledButton.icon(
          onPressed: working || selected.isEmpty ? null : import,
          icon: const Icon(Icons.download_outlined),
          label: Text('Import selected (${selected.length})'),
        ),
      ],
      body: SizedBox(
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Choose when the email arrived, then select one or more orders. Imported orders return to Pending orders for review.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        key: const ValueKey('reimport-date'),
                        onPressed: working ? null : chooseDay,
                        icon: const Icon(Icons.calendar_month_outlined),
                        label: Text(
                          MaterialLocalizations.of(context)
                              .formatMediumDate(day),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: working ? null : load,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Refresh'),
                      ),
                      TextButton(
                        onPressed: working || available.isEmpty
                            ? null
                            : () => setState(() {
                                if (selected.length == available.length) {
                                  selected.clear();
                                } else {
                                  selected.addAll(
                                    available.map(
                                      (entry) => entry['key'] as String,
                                    ),
                                  );
                                }
                              }),
                        child: Text(
                          selected.length == available.length &&
                                  available.isNotEmpty
                              ? 'Deselect all'
                              : 'Select available',
                        ),
                      ),
                    ],
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: loading
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Reading orders…'),
                        ],
                      ),
                    )
                  : candidates.isEmpty
                  ? Center(
                      child: Text(
                        error == null
                            ? 'No breakfast orders found for this day.'
                            : 'Could not load orders. Please try again.',
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: candidates.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final entry = candidates[index];
                        final key = entry['key'] as String;
                        final blocked = widget.email.importBlockReason(key);
                        return Material(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerLow,
                          borderRadius: BorderRadius.circular(8),
                          child: CheckboxListTile(
                            key: ValueKey('reimport-$key'),
                            value: selected.contains(key),
                            onChanged: working || blocked != null
                                ? null
                                : (value) => setState(() {
                                    if (value == true) {
                                      selected.add(key);
                                    } else {
                                      selected.remove(key);
                                    }
                                  }),
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(
                              '${guestCabin(entry).isEmpty ? 'Unknown cabin' : guestCabin(entry)} · ${entry['slot'] ?? 'Delivery needs review'}',
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                GuestContact(entry, compact: true),
                                const SizedBox(height: 4),
                                Text(
                                  blocked ??
                                      '${rows(entry['lines']).length} items · Available to import',
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
