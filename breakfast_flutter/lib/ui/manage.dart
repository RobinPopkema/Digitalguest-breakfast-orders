import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import '../controller.dart';
import '../model.dart';
import '../services/updates.dart';
import 'common.dart';
import 'app_update.dart';
import 'email_dialogs.dart';

class ManageDialog extends StatefulWidget {
  const ManageDialog(this.app, {super.key, this.initialSection = 0});
  final int initialSection;
  final AppController app;
  @override
  State<ManageDialog> createState() => _ManageDialogState();
}

class _ManageDialogState extends State<ManageDialog> {
  late Json draft;
  late int section;
  final names = <String, TextEditingController>{};
  final additions = {
    for (final key in ['categories', 'items', 'safeCabins'])
      key: TextEditingController(),
  };
  final additionFocus = {
    for (final key in ['categories', 'items', 'safeCabins']) key: FocusNode(),
  };
  String? newCategory;
  int newColor = 0;
  String cabinFilter = '';
  String? draggingItem;
  String? expandedCategory;
  String? draggingCategory;
  @override
  void initState() {
    super.initState();
    draft = clone(widget.app.data);
    expandedCategory = rows(draft['categories']).firstOrNull?['id'];
    section = widget.initialSection;
    widget.app.updates.addListener(startupUpdate);
    newColor = nextColor();
    for (final key in ['categories', 'items', 'safeCabins']) {
      for (final e in rows(draft[key])) {
        names[e['id']] = TextEditingController(text: e['name']);
      }
    }
  }

  void startupUpdate() {
    if (!mounted ||
        !widget.app.updates.startupNoticePending ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    widget.app.updates.startupNoticePending = false;
    setState(() => section = 4);
  }

  @override
  void dispose() {
    widget.app.updates.removeListener(startupUpdate);
    for (final c in additions.values) {
      c.dispose();
    }
    for (final f in additionFocus.values) {
      f.dispose();
    }
    for (final c in names.values) {
      c.dispose();
    }
    super.dispose();
  }

  int nextColor({int? previous}) {
    final counts = List.filled(palette.length, 0);
    for (final category in rows(draft['categories'])) {
      counts[(category['color'] as num? ?? 0).toInt() % palette.length]++;
    }
    final candidates = List.generate(
      palette.length,
      (i) => i,
    ).where((i) => i != previous).toList();
    return candidates.reduce((a, b) => counts[b] < counts[a] ? b : a);
  }

  void add(String key) {
    final name = additions[key]!.text.trim();
    if (name.isEmpty) {
      additionFocus[key]!.requestFocus();
      return;
    }
    if (key == 'items' && rows(draft['categories']).isEmpty) {
      showError(context, 'Add a category first.');
      return;
    }
    final category =
        findById(draft['categories'], newCategory)?['id'] ??
        rows(draft['categories']).firstOrNull?['id'];
    if (rows(draft[key]).any(
      (e) =>
          normalize(names[e['id']]!.text) == normalize(name) &&
          (key != 'items' || e['categoryId'] == category),
    )) {
      showError(
        context,
        'This name already exists${key == 'items' ? ' in this category' : ''}.',
      );
      additionFocus[key]!.requestFocus();
      return;
    }
    final id = newId();
    names[id] = TextEditingController(text: name);
    setState(() {
      draft[key].add({
        'id': id,
        'name': name,
        if (key == 'categories') 'color': newColor,
        if (key == 'items') 'categoryId': category,
      });
      if (key == 'categories') newColor = nextColor(previous: newColor);
      if (key == 'categories') expandedCategory = id;
      if (key == 'items') expandedCategory = category;
    });
    additions[key]!.clear();
    additionFocus[key]!.requestFocus();
  }

  Widget colorPicker(int value, ValueChanged<int> onChanged) => MenuAnchor(
    style: MenuStyle(
      side: WidgetStatePropertyAll(
        BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      shape: const WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
    ),
    menuChildren: [
      Padding(
        padding: const EdgeInsets.all(8),
        child: SizedBox(
          width: 240,
          child: Wrap(
            children: [
              for (var i = 0; i < palette.length; i++)
                SizedBox(
                  width: 40,
                  height: 40,
                  child: Builder(
                    builder: (context) => IconButton(
                      tooltip: colorNames[i],
                      onPressed: () {
                        onChanged(i);
                        MenuController.maybeOf(context)?.close();
                      },
                      icon: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: categoryFill(i),
                        ),
                        child: value == i
                            ? Icon(Icons.check, size: 16, color: categoryInk(i))
                            : null,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ],
    builder: (_, controller, child) => SizedBox(
      width: 44,
      child: IconButton(
        tooltip: 'Category color: ${colorNames[value]}',
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: categoryFill(value),
          ),
        ),
      ),
    ),
  );

  Widget categoryPicker(String? selected, ValueChanged<String?> onChanged) {
    final category = findById(draft['categories'], selected);
    final color = (category?['color'] as num? ?? 0).toInt() % 24;
    return SizedBox(
      width: 135,
      child: DropdownButtonFormField<String>(
        key: ValueKey('category-$selected-${category?['color']}'),
        initialValue: category?['id'],
        iconEnabledColor: categoryInk(color),
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'Category',
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          floatingLabelBehavior: FloatingLabelBehavior.never,
          fillColor: categoryFill(color),
          prefixIcon: Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: categoryInk(color),
                shape: BoxShape.circle,
              ),
            ),
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 30,
            maxWidth: 34,
          ),
        ),
        style: TextStyle(
          fontFamily: 'Segoe UI',
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: categoryInk(color),
        ),
        items: rows(draft['categories'])
            .map(
              (c) => DropdownMenuItem<String>(
                value: c['id'],
                child: CategoryBadge({...c, 'name': names[c['id']]!.text}),
              ),
            )
            .toList(),
        selectedItemBuilder: (_) => rows(draft['categories'])
            .map(
              (c) => Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  names[c['id']]!.text,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget entryRow(String key, {Json? entry, Widget? leading}) {
    final isNew = entry == null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          if (key == 'items' || key == 'categories')
            SizedBox(width: 32, child: leading),
          if (key == 'categories') ...[
            colorPicker(
              isNew ? newColor : (entry['color'] as num? ?? 0).toInt() % 24,
              (v) => setState(() {
                if (isNew) {
                  newColor = v;
                } else {
                  entry['color'] = v;
                }
              }),
            ),
            const SizedBox(width: 8),
          ],
          if (key == 'items') ...[
            categoryPicker(
              isNew
                  ? (findById(draft['categories'], newCategory)?['id'] ??
                        rows(draft['categories']).firstOrNull?['id'])
                  : entry['categoryId'],
              (v) => setState(() {
                if (isNew) {
                  newCategory = v;
                } else {
                  entry['categoryId'] = v;
                  expandedCategory = v;
                }
              }),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: TextField(
              key: isNew
                  ? ValueKey('add-$key')
                  : ValueKey('edit-${entry['id']}'),
              controller: isNew ? additions[key] : names[entry['id']],
              focusNode: isNew ? additionFocus[key] : null,
              textInputAction: isNew ? TextInputAction.done : null,
              onSubmitted: isNew ? (_) => add(key) : null,
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                floatingLabelBehavior: FloatingLabelBehavior.never,
                labelText: isNew
                    ? (key == 'items'
                          ? 'New item'
                          : key == 'categories'
                          ? 'New category'
                          : 'New cabin')
                    : (key == 'items'
                          ? 'Item name'
                          : key == 'categories'
                          ? 'Category name'
                          : 'Accommodation name'),
                hintText: isNew ? 'Type a name and press Enter' : null,
                suffixIcon: isNew
                    ? const Icon(Icons.keyboard_return, size: 18)
                    : null,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (key == 'categories')
            SizedBox(
              width: 44,
              child: isNew
                  ? null
                  : IconButton(
                      key: ValueKey('toggle-category-${entry['id']}'),
                      tooltip:
                          '${expandedCategory == entry['id'] ? 'Collapse' : 'Expand'} category',
                      onPressed: draggingItem != null
                          ? null
                          : () => setState(() {
                              expandedCategory = expandedCategory == entry['id']
                                  ? null
                                  : entry['id'];
                            }),
                      icon: Icon(
                        expandedCategory == entry['id']
                            ? Icons.expand_less
                            : Icons.expand_more,
                      ),
                    ),
            ),
          if (key == 'categories') const SizedBox(width: 8),
          if (key == 'items' || key == 'categories') ...[
            SizedBox(
              width: 44,
              child: isNew
                  ? null
                  : Tooltip(
                      message: key == 'categories'
                          ? (itemAvailable(entry)
                                ? 'Hide category'
                                : 'Show category')
                          : itemAvailable(entry)
                          ? 'Available — turn off to pause'
                          : 'Unavailable — turn on to restore',
                      child: Semantics(
                        toggled: itemAvailable(entry),
                        label: 'Availability for ${entry['name']}',
                        child: IconButton(
                          key: ValueKey('available-${entry['id']}'),
                          onPressed: () => setState(
                            () => entry['available'] = !itemAvailable(entry),
                          ),
                          icon: Icon(
                            itemAvailable(entry)
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),
            ),
          ],
          const SizedBox(width: 8),
          SizedBox(
            width: 44,
            child: isNew
                ? null
                : IconButton(
                    tooltip: 'Remove',
                    onPressed: () => remove(key, entry),
                    icon: const Icon(Icons.delete_outline),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> remove(String key, Json entry) async {
    if (!await confirm(
      context,
      'Remove ${entry['name']}?',
      key == 'categories'
          ? 'This removes the category and its menu items. Existing orders keep their details.'
          : key == 'safeCabins'
          ? 'Existing accepted orders keep their cabin names.'
          : 'Existing orders keep this item.',
      action: 'Remove',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      draft[key].remove(entry);
      if (key == 'categories') {
        draft['items'].removeWhere((i) => i['categoryId'] == entry['id']);
      }
    });
  }

  bool save({bool close = true}) {
    try {
      for (final key in ['categories', 'items', 'safeCabins']) {
        final seen = <String>{};
        for (final entry in rows(draft[key])) {
          entry['name'] = names[entry['id']]!.text.trim();
          if (entry['name'].isEmpty) throw StateError('Names cannot be empty.');
          final unique =
              (key == 'items' ? '${entry['categoryId']}\u0000' : '') +
              normalize(entry['name']);
          if (!seen.add(unique)) {
            throw StateError(
              'Category and cabin names, and item names within each category, must be unique.',
            );
          }
        }
      }
      widget.app.edit((data) {
        rows(draft['safeCabins'])
            .sort((a, b) => naturalCompare(a['name'], b['name']));
        for (final key in ['categories', 'items', 'safeCabins']) {
          data[key] = draft[key];
        }
        updateSnapshots(data);
      });
      if (close) Navigator.pop(context);
      return true;
    } catch (e) {
      showError(context, e);
      return false;
    }
  }

  void moveItem(String id, String categoryId, String? beforeId) {
    if (id == beforeId) return;
    setState(() {
      final all = rows(draft['items']);
      final item = findById(all, id);
      if (item == null || item['categoryId'] != categoryId) return;
      if (beforeId != null &&
          findById(all, beforeId)?['categoryId'] != categoryId) {
        return;
      }
      all.remove(item);
      final before = all.indexWhere((i) => i['id'] == beforeId);
      final last = all.lastIndexWhere((i) => i['categoryId'] == categoryId);
      all.insert(
        before >= 0
            ? before
            : last >= 0
            ? last + 1
            : all.length,
        item,
      );
    });
  }

  Widget itemDropZone(String categoryId, String? beforeId, Widget child) =>
      DragTarget<String>(
        key: ValueKey('drop-$categoryId-${beforeId ?? 'end'}'),
        onWillAcceptWithDetails: (details) =>
            details.data != beforeId &&
            findById(draft['items'], details.data)?['categoryId'] == categoryId,
        onAcceptWithDetails: (details) =>
            moveItem(details.data, categoryId, beforeId),
        builder: (context, candidates, rejected) => Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: candidates.isEmpty ? 0 : 48,
              margin: EdgeInsets.only(bottom: candidates.isEmpty ? 0 : 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: candidates.isEmpty
                  ? null
                  : const Center(child: Text('Drop item here')),
            ),
            child,
          ],
        ),
      );

  Widget itemDragHandle(Json item) => Draggable<String>(
    key: ValueKey('drag-item-${item['id']}'),
    data: item['id'],
    onDragStarted: () => setState(() => draggingItem = item['id']),
    onDragEnd: (_) {
      if (mounted) setState(() => draggingItem = null);
    },
    feedback: Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          names[item['id']]!.text,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    ),
    child: const Tooltip(
      message: 'Drag to reorder within this category',
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: SizedBox(
          width: 32,
          height: 44,
          child: Icon(Icons.drag_indicator, size: 20),
        ),
      ),
    ),
  );

  void finishCategoryDrag() {
    if (!mounted || draggingCategory == null) return;
    setState(() {
      expandedCategory = draggingCategory;
      draggingCategory = null;
    });
  }

  Widget categoryProxy(Widget child, int index, Animation<double> animation) {
    final category = findById(draft['categories'], draggingCategory)!;
    return _CategoryDragProxy(
      onRemoved: finishCategoryDrag,
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          key: const ValueKey('category-drag-preview'),
          height: 60,
          child: Row(
            children: [
              const SizedBox(width: 16),
              const Icon(Icons.drag_indicator),
              const SizedBox(width: 12),
              Flexible(
                child: CategoryBadge({
                  ...category,
                  'name': names[category['id']]!.text,
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget groupedItems() {
    final categories = rows(draft['categories']);
    final categoryIds = categories.map((category) => category['id']).toSet();
    final grouped = <String, List<Json>>{};
    for (final item in rows(draft['items'])) {
      (grouped[item['categoryId'] as String] ??= []).add(item);
    }
    final missing = grouped.keys.where((id) => !categoryIds.contains(id));
    Widget itemsIn(String categoryId) => Column(
      children: [
        for (final item in grouped[categoryId] ?? <Json>[])
          itemDropZone(
            categoryId,
            item['id'],
            Opacity(
              opacity: draggingItem == item['id'] ? .35 : 1,
              child: entryRow(
                'items',
                entry: item,
                leading: itemDragHandle(item),
              ),
            ),
          ),
        itemDropZone(
          categoryId,
          null,
          SizedBox(
            height: draggingItem == null ? 8 : 36,
            width: double.infinity,
          ),
        ),
      ],
    );
    return ReorderableListView(
      key: const ValueKey('category-sections'),
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      header: Column(
        children: [
          entryRow('categories'),
          entryRow('items'),
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'Expand a category to edit its items. Drag items within their category to reorder.',
            ),
          ),
        ],
      ),
      footer: Column(
        children: [
          for (final id in missing) ...[
            TextButton(
              onPressed: () => setState(
                () => expandedCategory = expandedCategory == id ? null : id,
              ),
              child: const Text('Unassigned category'),
            ),
            if (expandedCategory == id) itemsIn(id),
          ],
        ],
      ),
      onReorderStart: (index) => setState(() {
        draggingCategory = categories[index]['id'];
        expandedCategory = null;
      }),
      proxyDecorator: categoryProxy,
      onReorderItem: (oldIndex, newIndex) => setState(() {
        categories.insert(newIndex, categories.removeAt(oldIndex));
      }),
      children: [
        for (var i = 0; i < categories.length; i++)
          Container(
            key: ValueKey('item-section-${categories[i]['id']}'),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            child: Column(
              children: [
                entryRow(
                  'categories',
                  entry: categories[i],
                  leading: Listener(
                    onPointerDown: (_) =>
                        setState(() => expandedCategory = null),
                    onPointerUp: (_) {
                      if (draggingCategory == null) {
                        setState(() => expandedCategory = categories[i]['id']);
                      }
                    },
                    onPointerCancel: (_) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        if (draggingCategory != null) {
                          finishCategoryDrag();
                        } else {
                          setState(
                            () => expandedCategory = categories[i]['id'],
                          );
                        }
                      });
                    },
                    child: _CategoryDragStartListener(
                      key: ValueKey('drag-category-${categories[i]['id']}'),
                      index: i,
                      child: const Tooltip(
                        message: 'Drag category and all its items',
                        child: MouseRegion(
                          cursor: SystemMouseCursors.grab,
                          child: SizedBox(
                            width: 32,
                            height: 44,
                            child: Icon(Icons.drag_indicator, size: 20),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (expandedCategory == categories[i]['id'])
                  itemsIn(categories[i]['id']),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> editCabin(Json cabin) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _CabinNameDialog(
        initial: names[cabin['id']]!.text,
        duplicate: (value) => rows(draft['safeCabins']).any(
          (c) =>
              c['id'] != cabin['id'] &&
              normalize(names[c['id']]!.text) == normalize(value),
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        names[cabin['id']]!.text = result;
        cabin['name'] = result;
      });
    }
  }

  Widget cabinsPage() => ListView(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
    children: [
      entryRow('safeCabins'),
      TextField(
        key: const ValueKey('search-cabins'),
        onChanged: (value) => setState(() => cabinFilter = value),
        decoration: const InputDecoration(
          labelText: 'Search cabins',
          prefixIcon: Icon(Icons.search),
        ),
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final cabin in rows(draft['safeCabins']).where(
            (c) =>
                normalize(names[c['id']]!.text)
                    .contains(normalize(cabinFilter)),
          ))
            Container(
              key: ValueKey('cabin-pill-${cabin['id']}'),
              padding: const EdgeInsets.only(left: 14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 200),
                    child: Tooltip(
                      message: names[cabin['id']]!.text,
                      child: Text(
                        names[cabin['id']]!.text,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Edit cabin ${names[cabin['id']]!.text}',
                    onPressed: () => editCabin(cabin),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Delete cabin ${names[cabin['id']]!.text}',
                    onPressed: () => remove('safeCabins', cabin),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
            ),
        ],
      ),
    ],
  );

  Future<void> backup() async {
    try {
      await widget.app.backup();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> restore() async {
    try {
      final next = await widget.app.chooseRestore();
      if (next == null || !mounted) return;
      if (!await confirm(
        context,
        'Restore data?',
        'Replace the current menu and orders with ${next['orders'].length} orders, ${next['categories'].length} categories and ${next['items'].length} items? Unsaved settings edits will be discarded. A previous-file backup is retained.',
        action: 'Restore',
      )) {
        return;
      }
      widget.app.commit(next);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Widget backupPage() => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const Text(
        'Back up saved menu items, orders, accommodations and preferences. Email credentials and pending imports are not included. Save any menu edits before creating a backup.',
      ),
      const SizedBox(height: 20),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          FilledButton.icon(
            onPressed: backup,
            icon: const Icon(Icons.download_outlined),
            label: const Text('Back up data'),
          ),
          OutlinedButton.icon(
            onPressed: restore,
            icon: const Icon(Icons.restore),
            label: const Text('Restore data'),
          ),
        ],
      ),
    ],
  );

  Widget aboutPage() => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Row(
        children: [
          Image.asset('assets/icon-256.png', width: 56),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Breakfast Orders',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                Text('Version $appVersion'),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 24),
      ListenableBuilder(
        listenable: widget.app.updates,
        builder: (context, _) {
          final updates = widget.app.updates;
          final release = updates.available;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (release != null)
                Card.filled(
                  key: const ValueKey('update-notice'),
                  color: Theme.of(context).colorScheme.primaryContainer,
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.system_update_alt, size: 32),
                        const SizedBox(height: 12),
                        Text(
                          'A new version is available',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Version ${release['version']} is ready to install.',
                        ),
                        if ('${release['notes'] ?? ''}'.trim().isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text('${release['notes']}'),
                        ],
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: updates.installing
                              ? null
                              : () => installAppUpdate(
                                  context,
                                  widget.app,
                                  beforeInstall: () => save(close: false),
                                ),
                          icon: const Icon(Icons.system_update_alt),
                          label: const Text('Update and restart'),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                updates.error ??
                    (!updates.configured
                        ? 'Update repository is not configured in this build.'
                        : updates.checking
                        ? 'Checking for updates…'
                        : release == null
                        ? 'No newer release found.'
                        : 'Your saved orders and settings will be kept.'),
              ),
              const SizedBox(height: 8),
              const Text(
                'Updates are checked once at startup. You can also check manually.',
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed:
                    updates.checking ||
                        updates.installing ||
                        !updates.configured
                    ? null
                    : updates.check,
                icon: const Icon(Icons.refresh),
                label: Text(
                  updates.checking ? 'Checking…' : 'Check for updates',
                ),
              ),
            ],
          );
        },
      ),
      const SizedBox(height: 24),
      const Divider(),
      const SizedBox(height: 16),
      Text('Your data', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      const Text(
        'Compatible with Breakfast Orders 1.22.2 data and print layouts.',
      ),
      const SizedBox(height: 8),
      SelectableText('Data folder: ${widget.app.store.directory.path}'),
      const SizedBox(height: 24),
      Text('Licenses', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      const Text('Third-party software and open-source acknowledgements.'),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton(
          onPressed: () => showLicensePage(
            context: context,
            applicationName: 'Breakfast Orders',
            applicationVersion: appVersion,
          ),
          child: const Text('View licenses'),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    const labels = [
      'Menu',
      'Cabins',
      'Email',
      'Backup & restore',
      'About & licenses',
    ];
    const icons = [
      Icons.restaurant_menu,
      Icons.cabin_outlined,
      Icons.mail_outline,
      Icons.backup_outlined,
      Icons.info_outline,
    ];
    return EditorDialog(
      title: 'Settings',
      width: settingsContentWidth,
      headerActions: [
        FilledButton(
          onPressed: () => save(),
          child: const Text('Save all changes'),
        ),
      ],
      body: SizedBox(
        height: 560,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 180,
              child: Material(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                child: Column(
                  children: [
                    for (var i = 0; i < labels.length; i++) ...[
                      if (i == 4) const Spacer(),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: ListTile(
                          key: ValueKey('settings-section-$i'),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                          ),
                          leading: Icon(icons[i], size: 20),
                          minLeadingWidth: 20,
                          horizontalTitleGap: 8,
                          title: Text(
                            labels[i],
                            style: const TextStyle(fontSize: 13),
                          ),
                          selected: section == i,
                          selectedTileColor: Theme.of(context)
                              .colorScheme
                              .secondaryContainer,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          onTap: () => setState(() => section = i),
                        ),
                      ),
                    ],
                    const Divider(),
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      title: const Text(
                        'Dark mode',
                        style: TextStyle(fontSize: 13),
                      ),
                      value: widget.app.darkMode,
                      onChanged: (value) {
                        try {
                          widget.app.setDarkMode(value);
                          setState(() {});
                        } catch (error) {
                          showError(context, error);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Text(
                      labels[section],
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Expanded(
                    child: IndexedStack(
                      index: section,
                      sizing: StackFit.expand,
                      children: [
                        for (final key in ['items', 'safeCabins'])
                          Column(
                            children: [
                              const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text(
                                  'Edit entries, then save them together. Existing orders retain removed items and accommodation names.',
                                ),
                              ),
                              Expanded(
                                child: key == 'items'
                                    ? groupedItems()
                                    : cabinsPage(),
                              ),
                            ],
                          ),
                        EmailSettings(widget.app, embedded: true),
                        backupPage(),
                        aboutPage(),
                      ],
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

class _CabinNameDialog extends StatefulWidget {
  const _CabinNameDialog({required this.initial, required this.duplicate});
  final String initial;
  final bool Function(String) duplicate;
  @override
  State<_CabinNameDialog> createState() => _CabinNameDialogState();
}

class _CabinNameDialogState extends State<_CabinNameDialog> {
  late final controller = TextEditingController(text: widget.initial);
  String? error;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void submit() {
    final value = controller.text.trim();
    if (value.isEmpty || widget.duplicate(value)) {
      setState(
        () => error = value.isEmpty
            ? 'Enter a cabin name.'
            : 'This cabin already exists.',
      );
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit cabin'),
    content: SizedBox(
      width: 360,
      child: TextField(
        key: const ValueKey('edit-cabin-name'),
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: 'Cabin name', errorText: error),
        onSubmitted: (_) => submit(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: submit, child: const Text('Save cabin')),
    ],
  );
}

// Reopening changes row heights, so wait until Flutter has removed the drag
// overlay and its placeholder, including no-op drops and cancelled drags.
class _CategoryDragProxy extends StatefulWidget {
  const _CategoryDragProxy({required this.child, required this.onRemoved});
  final Widget child;
  final VoidCallback onRemoved;
  @override
  State<_CategoryDragProxy> createState() => _CategoryDragProxyState();
}

class _CategoryDragProxyState extends State<_CategoryDragProxy> {
  @override
  Widget build(BuildContext context) => widget.child;

  @override
  void dispose() {
    final onRemoved = widget.onRemoved;
    WidgetsBinding.instance.addPostFrameCallback((_) => onRemoved());
    super.dispose();
  }
}

class _CategoryDragStartListener extends StatelessWidget {
  const _CategoryDragStartListener({
    super.key,
    required this.index,
    required this.child,
  });
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) {
      final localAnchor = event.localPosition;
      SliverReorderableList.of(context).startItemDragReorder(
        index: index,
        event: event,
        recognizer: _CollapsedCategoryDragRecognizer(
          () => (context.findRenderObject()! as RenderBox).localToGlobal(
            localAnchor,
          ),
        )..gestureSettings = MediaQuery.maybeGestureSettingsOf(context),
      );
    },
    child: child,
  );
}

class _CollapsedCategoryDragRecognizer
    extends ImmediateMultiDragGestureRecognizer {
  _CollapsedCategoryDragRecognizer(this.anchor) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _layoutReady = true;
      if (!_disposed && _pendingPointer != null) _accept(_pendingPointer!);
    });
  }
  final Offset Function() anchor;
  bool _disposed = false, _layoutReady = false;
  int? _pendingPointer;

  @override
  void acceptGesture(int pointer) {
    if (_layoutReady) {
      _accept(pointer);
    } else {
      _pendingPointer = pointer;
    }
  }

  void _accept(int pointer) {
    // Measure after collapse, keeping the preview at the actual pointer even
    // when closing an earlier category moves this handle upwards.
    final start = onStart;
    onStart = (position) {
      final origin = anchor();
      final drag = start?.call(origin);
      drag?.update(
        DragUpdateDetails(delta: position - origin, globalPosition: position),
      );
      return drag;
    };
    super.acceptGesture(pointer);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
