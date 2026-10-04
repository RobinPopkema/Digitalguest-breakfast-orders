import 'package:flutter/material.dart';

import '../controller.dart';
import '../model.dart';
import '../services/email_parser.dart';
import 'common.dart';

class EmailSettings extends StatefulWidget {
  const EmailSettings(this.app, {super.key, this.embedded = false});
  final bool embedded;
  final AppController app;
  @override
  State<EmailSettings> createState() => _EmailSettingsState();
}

class _EmailSettingsState extends State<EmailSettings> {
  final fields = <String, TextEditingController>{};
  bool enabled = false, working = false;
  List<String> folders = [];
  String? error;
  late List<int> intervals;
  @override
  void initState() {
    super.initState();
    final draft = {...widget.app.email.config, ...widget.app.settingsDraft};
    for (final key in [
      'host',
      'port',
      'user',
      'password',
      'folder',
      'intervalMinutes',
      'sender',
    ]) {
      fields[key] = TextEditingController(
        text: key == 'password'
            ? ''
            : '${draft[key] ?? (key == 'port'
                      ? 993
                      : key == 'intervalMinutes'
                      ? 1
                      : key == 'sender'
                      ? defaultSender
                      : '')}',
      );
    }
    final savedInterval = int.tryParse(fields['intervalMinutes']!.text) ?? 1;
    intervals = {
      for (var i = 1; i <= 60; i++) i,
      for (var i = 75; i <= 1440; i += 15) i,
      savedInterval.clamp(1, 1440),
    }.toList()..sort();
    fields['intervalMinutes']!.text = savedInterval.clamp(1, 1440).toString();
    enabled = draft['enabled'] == true;
    widget.app.email.addListener(refreshStatus);
  }

  void refreshStatus() {
    if (mounted) setState(() {});
  }

  Json get input => {
    for (final entry in fields.entries) entry.key: entry.value.text,
    'enabled': enabled,
  };
  @override
  void dispose() {
    widget.app.email.removeListener(refreshStatus);
    final draft = input;
    draft.remove('password');
    widget.app.settingsDraft = draft;
    for (final f in fields.values) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> run(Future<void> Function() task) async {
    setState(() {
      working = true;
      error = null;
    });
    try {
      await task();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Widget field(String key, String label, {bool secret = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextField(
      controller: fields[key],
      obscureText: secret,
      autocorrect: false,
      enableSuggestions: !secret,
      decoration: InputDecoration(labelText: label),
    ),
  );
  Future<void> save(bool check) async {
    await widget.app.email.saveSettings(input);
    if (!mounted) return;
    fields['password']!.clear();
    if (check) await widget.app.email.check();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[
      TextButton(
        onPressed: working
            ? null
            : () => run(() async {
                widget.app.email.pause();
                enabled = false;
              }),
        child: const Text('Pause checks'),
      ),
      OutlinedButton(
        onPressed: working ? null : () => run(() => save(false)),
        child: const Text('Test connection & save'),
      ),
      FilledButton(
        onPressed: working ? null : () => run(() => save(true)),
        child: const Text('Save & check'),
      ),
    ];
    final body = SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Checks read today’s DigitalGuest messages from one folder. Emails are never moved, deleted, or marked as read.',
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(flex: 3, child: field('host', 'IMAP server')),
              const SizedBox(width: 12),
              Expanded(child: field('port', 'TLS port')),
            ],
          ),
          field('user', 'Email account / username'),
          field(
            'password',
            widget.app.email.configured
                ? 'Password (leave empty to keep saved password)'
                : 'Password or app password',
            secret: true,
          ),
          OutlinedButton.icon(
            onPressed: working
                ? null
                : () => run(() async {
                    folders = await widget.app.email.folders(input);
                  }),
            icon: const Icon(Icons.folder_open),
            label: const Text('Connect & list folders'),
          ),
          const SizedBox(height: 16),
          field('folder', 'Exact folder to watch'),
          if (folders.isNotEmpty)
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'Folders from server',
              ),
              items: folders
                  .map(
                    (f) => DropdownMenuItem(
                      value: f,
                      child: Text(f, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: (f) => fields['folder']!.text = f!,
            ),
          const SizedBox(height: 12),
          Text(
            'Check every ${fields['intervalMinutes']!.text} ${fields['intervalMinutes']!.text == '1' ? 'minute' : 'minutes'}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Slider(
            key: const ValueKey('check-interval-slider'),
            min: 0,
            max: (intervals.length - 1).toDouble(),
            divisions: intervals.length - 1,
            value: intervals
                .indexOf(int.parse(fields['intervalMinutes']!.text))
                .toDouble(),
            label: '${fields['intervalMinutes']!.text} min',
            semanticFormatterCallback: (value) =>
                '${intervals[value.round()]} minutes',
            onChanged: working
                ? null
                : (value) => setState(() {
                    fields['intervalMinutes']!.text = intervals[value.round()]
                        .toString();
                  }),
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text('1 minute'), Text('24 hours')],
            ),
          ),
          field('sender', 'Exact DigitalGuest sender'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Automatic checks while the app is open'),
            value: enabled,
            onChanged: working ? null : (v) => setState(() => enabled = v),
          ),
          if (working) const LinearProgressIndicator(),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 12),
          Text(widget.app.email.message),
          const SizedBox(height: 12),
          const Text(
            'Password / app-password accounts are supported. OAuth-only accounts require a supported app password. Your password is protected by this Windows account and is excluded from data backups.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
    if (widget.embedded) {
      return Column(
        children: [
          Expanded(child: body),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(spacing: 8, runSpacing: 8, children: actions),
          ),
        ],
      );
    }
    return EditorDialog(
      title: 'Email orders · settings',
      width: 660,
      actions: actions,
      body: body,
    );
  }
}

class EmailReview extends StatefulWidget {
  const EmailReview(this.app, this.entry, {super.key, this.selectedCabin});
  final AppController app;
  final Json entry;
  final String? selectedCabin;
  @override
  State<EmailReview> createState() => _EmailReviewState();
}

class _EmailReviewState extends State<EmailReview> {
  late List<Json> lines;
  late String slot;
  String? cabin;
  bool confirmed = false;
  final comment = TextEditingController();
  final firstUnmatched = FocusNode();
  @override
  void initState() {
    super.initState();
    final ids = widget.app.email.matches(widget.entry);
    lines = List.generate(
      ids.length,
      (i) => {
        'needsReview': ids[i].isEmpty,
        'sourceIndex': i,
        'itemId': ids[i],
        'qty': widget.entry['lines'][i]['qty'],
        'sourceName': widget.entry['lines'][i]['name'],
      },
    );
    slot = widget.entry['slot'] ?? '';
    cabin =
        widget.selectedCabin ?? widget.app.email.matchingCabin(widget.entry);
    comment.text = widget.entry['comment'] ?? '';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) firstUnmatched.requestFocus();
    });
  }

  @override
  void dispose() {
    comment.dispose();
    firstUnmatched.dispose();
    super.dispose();
  }

  void accept() {
    try {
      widget.app.email.accept({
        'id': widget.entry['id'],
        'safeCabinId': cabin,
        'slot': slot,
        'comment': comment.text,
        'confirmed': confirmed,
        'lines': lines,
      });
      Navigator.pop(context);
    } catch (e) {
      showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.app.data;
    final unresolved = lines.where((l) => l['needsReview'] == true).toList();
    final first = unresolved.firstOrNull;
    final colors = Theme.of(context).colorScheme;
    return EditorDialog(
      title: 'Review pending order · ${guestCabin(widget.entry)}',
      actions: [
        TextButton(
          onPressed: () async {
            if (await confirm(
              context,
              'Dismiss email order?',
              'The email stays untouched and will not be imported again.',
              action: 'Dismiss',
            )) {
              try {
                widget.app.email.dismiss(widget.entry['id']);
                if (context.mounted) Navigator.pop(context);
              } catch (e) {
                if (context.mounted) showError(context, e);
              }
            }
          },
          child: const Text('Dismiss'),
        ),
        FilledButton(
          onPressed: accept,
          child: const Text('Accept breakfast order'),
        ),
      ],
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GuestContact(widget.entry),
            const SizedBox(height: 16),
            for (final warning in widget.entry['warnings'] ?? [])
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '$warning',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: cabin,
                    decoration: const InputDecoration(
                      labelText: 'Select cabin',
                    ),
                    items: rows(data['safeCabins'])
                        .map(
                          (c) => DropdownMenuItem(
                            value: c['id'] as String,
                            child: Text(c['name']),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => cabin = v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: slots.contains(slot) ? slot : null,
                    decoration: const InputDecoration(
                      labelText: 'Delivery time',
                    ),
                    items: slots
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) => setState(() => slot = v!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              unresolved.isEmpty ? 'All items matched automatically.' : 'Match the items below to available menu items. Unavailable items need a replacement. Other items were matched automatically.',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            for (final line in unresolved)
              Container(
                key: ValueKey('review-line-${line['sourceIndex']}'),
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${line['sourceName']}',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: colors.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: colors.primaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '× ${line['qty']}',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: colors.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: ValueKey('map-${line['sourceIndex']}'),
                      focusNode: identical(line, first) ? firstUnmatched : null,
                      initialValue:
                          findById(data['items'], line['itemId']) == null
                          ? null
                          : line['itemId'],
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Match to menu item',
                      ),
                      items: rows(data['items'])
                          .where(itemAvailable)
                          .map(
                            (item) => DropdownMenuItem(
                              value: item['id'] as String,
                              child: Row(
                                children: [
                                  Flexible(
                                    child: CategoryBadge(
                                      findById(
                                            data['categories'],
                                            item['categoryId'],
                                          ) ??
                                          {'name': 'Removed category'},
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      item['name'],
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setState(() => line['itemId'] = value),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            TextField(
              controller: comment,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Order comment'),
            ),
            const SizedBox(height: 16),
            ShowEmailButton(widget.entry),
            ExpansionTile(
              title: const Text('Read original email text'),
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText('${widget.entry['text'] ?? ''}'),
                ),
              ],
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: confirmed,
              onChanged: (v) => setState(() => confirmed = v!),
              title: const Text(
                'I checked the cabin, time and items. This is a breakfast order.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
