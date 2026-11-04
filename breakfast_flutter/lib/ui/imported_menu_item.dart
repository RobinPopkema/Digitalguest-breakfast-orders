import 'package:flutter/material.dart';

import '../controller.dart';
import '../model.dart';
import 'common.dart';

class ImportedMenuItem extends StatefulWidget {
  const ImportedMenuItem(this.app, this.sourceName, {super.key});
  final AppController app;
  final String sourceName;

  @override
  State<ImportedMenuItem> createState() => _ImportedMenuItemState();
}

class _ImportedMenuItemState extends State<ImportedMenuItem> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.sourceName);
  final categoryName = TextEditingController();
  String categoryId = '';

  @override
  void dispose() {
    name.dispose();
    categoryName.dispose();
    super.dispose();
  }

  void save() {
    if (!form.currentState!.validate()) return;
    try {
      final itemId = newId();
      widget.app.edit((data) {
        var category = findById(data['categories'], categoryId);
        if (categoryId.isEmpty) {
          if (rows(
            data['categories'],
          ).any((c) => normalize(c['name']) == normalize(categoryName.text))) {
            throw StateError(
              'This category already exists. Select it from the list.',
            );
          }
          final counts = List.filled(palette.length, 0);
          for (final c in rows(data['categories'])) {
            counts[(c['color'] as num? ?? 0).toInt() % palette.length]++;
          }
          final color = List.generate(
            palette.length,
            (i) => i,
          ).reduce((a, b) => counts[b] < counts[a] ? b : a);
          category = {
            'id': newId(),
            'name': categoryName.text.trim(),
            'color': color,
          };
          data['categories'].add(category);
        }
        if (category == null || category['available'] == false) {
          throw StateError('Select an available category.');
        }
        if (rows(data['items']).any(
          (item) =>
              item['categoryId'] == category!['id'] &&
              normalize(item['name']) == normalize(name.text),
        )) {
          throw StateError(
            'This item already exists in the category. Map it to the existing item instead.',
          );
        }
        data['items'].add({
          'id': itemId,
          'name': name.text.trim(),
          'categoryId': category['id'],
        });
      });
      Navigator.pop(context, itemId);
    } catch (error) {
      showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) => EditorDialog(
    title: 'Add menu item',
    actions: [
      FilledButton(onPressed: save, child: const Text('Add & use item')),
    ],
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const ValueKey('import-item-name'),
              controller: name,
              decoration: const InputDecoration(labelText: 'Menu item name'),
              validator: (value) =>
                  value!.trim().isEmpty ? 'Enter an item name.' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: const ValueKey('import-item-category'),
              initialValue: categoryId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                const DropdownMenuItem(value: '', child: Text('New category…')),
                for (final category in rows(widget.app.data['categories']))
                  if (category['available'] != false)
                    DropdownMenuItem(
                      value: category['id'] as String,
                      child: CategoryBadge(category),
                    ),
              ],
              onChanged: (value) => setState(() => categoryId = value!),
            ),
            if (categoryId.isEmpty) ...[
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('import-category-name'),
                controller: categoryName,
                decoration: const InputDecoration(
                  labelText: 'New category name',
                ),
                validator: (value) =>
                    value!.trim().isEmpty ? 'Enter a category name.' : null,
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'This saves the item to your menu and selects it for this order. The order stays pending until accepted.',
            ),
          ],
        ),
      ),
    ),
  );
}
