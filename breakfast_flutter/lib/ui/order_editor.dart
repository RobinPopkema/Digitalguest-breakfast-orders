import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller.dart';
import '../model.dart';
import '../services/email_parser.dart';
import 'common.dart';

class OrderEditor extends StatefulWidget {
  const OrderEditor(this.app, {this.order, super.key});
  final AppController app;
  final Json? order;
  @override
  State<OrderEditor> createState() => _OrderEditorState();
}

class _OrderEditorState extends State<OrderEditor> {
  final search = TextEditingController(),
      room = TextEditingController(),
      comment = TextEditingController();
  final searchFocus = FocusNode(),
      roomFocus = FocusNode(),
      commentFocus = FocusNode();
  final quantities = <String, int>{};
  late String slot;
  final guestFields = {
    for (final key in ['name', 'email', 'phone']) key: TextEditingController(),
  };
  final guestFocus = {
    for (final key in ['name', 'email', 'phone']) key: FocusNode(),
  };
  @override
  void initState() {
    super.initState();
    room.text = widget.order?['room'] ?? '';
    final guest = guestDetails(widget.order ?? {});
    for (final key in guestFields.keys) {
      guestFields[key]!.text = '${guest[key] ?? ''}';
    }
    comment.text = widget.order?['comment'] ?? '';
    slot = widget.order?['slot'] ?? slots.first;
    for (final line in rows(widget.order?['lines'] ?? [])) {
      if (line['itemId'] != null) {
        quantities[line['itemId']] = (line['qty'] as num).toInt();
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      searchFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    for (final c in [search, room, comment, ...guestFields.values]) {
      c.dispose();
    }
    for (final f in [
      searchFocus,
      roomFocus,
      commentFocus,
      ...guestFocus.values,
    ]) {
      f.dispose();
    }
    super.dispose();
  }

  void quantity(String id, int step) {
    final item = findById(widget.app.data['items'], id);
    if (step > 0 && item != null && !itemAvailable(item)) return;
    setState(
      () => quantities[id] = ((quantities[id] ?? 0) + step).clamp(0, 10000),
    );
    searchFocus.requestFocus();
    search.selection = TextSelection(
      baseOffset: 0,
      extentOffset: search.text.length,
    );
  }

  void save() {
    if (room.text.trim().isEmpty) {
      roomFocus.requestFocus();
      showError(context, 'Select an accommodation.');
      return;
    }
    try {
      widget.app.edit((data) {
        final old = findById(data['orders'], widget.order?['id']);
        final lines = <Json>[];
        for (final item in rows(data['items'])) {
          final qty = quantities[item['id']] ?? 0;
          final oldQty = rows(old?['lines'] ?? [])
              .where((l) => l['itemId'] == item['id'])
              .fold<num>(0, (sum, l) => sum + (l['qty'] as num));
          if (!itemAvailable(item) && qty > oldQty) {
            throw StateError('${item['name']} is unavailable.');
          }
          if (qty > 0) {
            lines.add(
              lineFor(
                item,
                findById(data['categories'], item['categoryId']) ??
                    {'id': item['categoryId'], 'name': '', 'color': 0},
                qty,
              ),
            );
          }
        }
        if (old != null) {
          lines.addAll(
            rows(old['lines'])
                .where((l) => findById(data['items'], l['itemId']) == null),
          );
        }
        final result = {
          ...?old,
          'id': old?['id'] ?? newId(),
          'room': room.text.trim(),
          'slot': slot,
          'comment': comment.text.trim(),
          'guest': {
            ...guestDetails(old ?? {}),
            for (final entry in guestFields.entries)
              entry.key: entry.value.text.trim(),
          },
          'lines': lines,
        };
        if (old != null) {
          data['orders'][data['orders'].indexOf(old)] = result;
        } else {
          data['orders'].add(result);
        }
      });
      Navigator.pop(context);
    } catch (e) {
      showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.app.data, query = normalize(search.text);
    final cabinNames = {
      for (final cabin in rows(data['safeCabins'])) cabin['name'] as String,
      if (widget.order != null && '${widget.order!['room']}'.isNotEmpty)
        widget.order!['room'] as String,
    };
    return Focus(
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent ||
            roomFocus.hasFocus ||
            guestFocus.values.any((focus) => focus.hasFocus) ||
            commentFocus.hasFocus ||
            searchFocus.hasFocus ||
            HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isAltPressed ||
            HardwareKeyboard.instance.isMetaPressed) {
          return KeyEventResult.ignored;
        }
        final text = event.character;
        if (text != null && text.isNotEmpty) {
          searchFocus.requestFocus();
          setState(() => search.text = text);
          search.selection = TextSelection.collapsed(
            offset: search.text.length,
          );
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: EditorDialog(
        title: widget.order == null
            ? 'New breakfast order'
            : 'Edit breakfast order',
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: save,
            icon: const Icon(Icons.check),
            label: const Text('Save order'),
          ),
        ],
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          key: const ValueKey('order-cabin'),
                          focusNode: roomFocus,
                          isExpanded: true,
                          initialValue: room.text.isEmpty ? null : room.text,
                          decoration: const InputDecoration(
                            labelText: 'Select cabin',
                          ),
                          hint: Text(
                            rows(data['safeCabins']).isEmpty
                                ? 'No accommodations configured'
                                : 'Choose accommodation',
                          ),
                          items: cabinNames
                              .map(
                                (name) => DropdownMenuItem(
                                  value: name,
                                  child: Text(
                                    name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: cabinNames.isEmpty
                              ? null
                              : (value) => setState(() => room.text = value!),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: slots.contains(slot) ? slot : null,
                          decoration: const InputDecoration(
                            labelText: 'Delivery time',
                          ),
                          items: slots
                              .map(
                                (s) =>
                                    DropdownMenuItem(value: s, child: Text(s)),
                              )
                              .toList(),
                          onChanged: (s) => setState(() => slot = s!),
                        ),
                      ),
                    ],
                  ),
                  if (widget.order == null && rows(data['safeCabins']).isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Add accommodations in Settings → Cabins before creating an order.',
                      ),
                    ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      for (final key in guestFields.keys) ...[
                        if (key != 'name') const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            key: ValueKey('guest-$key'),
                            controller: guestFields[key],
                            focusNode: guestFocus[key],
                            keyboardType: key == 'email'
                                ? TextInputType.emailAddress
                                : key == 'phone'
                                ? TextInputType.phone
                                : TextInputType.name,
                            decoration: InputDecoration(
                              labelText: key == 'name'
                                  ? 'Guest name'
                                  : key == 'email'
                                  ? 'Email'
                                  : 'Phone',
                              prefixIcon: Icon(
                                key == 'name'
                                    ? Icons.person_outline
                                    : key == 'email'
                                    ? Icons.alternate_email
                                    : Icons.phone_outlined,
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: search,
                    focusNode: searchFocus,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      labelText: 'Search items or categories',
                      suffixIcon: search.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              onPressed: () => setState(search.clear),
                              icon: const Icon(Icons.close),
                            ),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                children: [
                  if (rows(data['items']).isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Your menu is empty. Add categories and items in Manage menu.',
                      ),
                    ),
                  for (final category in rows(data['categories'])) ...[
                    if (rows(data['items']).any(
                      (i) =>
                          i['categoryId'] == category['id'] &&
                          (normalize(i['name']).contains(query) ||
                              normalize(category['name']).contains(query)),
                    )) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: CategoryBadge(category),
                        ),
                      ),
                      for (final item in rows(data['items']).where(
                        (i) =>
                            i['categoryId'] == category['id'] &&
                            (normalize(i['name']).contains(query) ||
                                normalize(category['name']).contains(query)),
                      ))
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(item['name']),
                          subtitle: itemAvailable(item)
                              ? null
                              : const Text('Unavailable'),
                          trailing: QuantityStepper(
                            name: item['name'],
                            canIncrease: itemAvailable(item),
                            value: quantities[item['id']] ?? 0,
                            onChange: (step) => quantity(item['id'], step),
                          ),
                        ),
                    ],
                  ],
                  if (widget.order != null &&
                      rows(widget.order!['lines']).any(
                        (l) => findById(data['items'], l['itemId']) == null,
                      ))
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Items removed from the menu are retained on this order.',
                      ),
                    ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: comment,
                    focusNode: commentFocus,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Order comment',
                      hintText: 'Delivery instructions or dietary notes',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
