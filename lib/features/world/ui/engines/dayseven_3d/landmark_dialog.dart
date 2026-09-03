/// Dialog for adding and editing landmark pins on the DaySeven 3D globe.
library;

import 'package:flutter/material.dart';

import 'package:dayseven/features/world/application/world_controller.dart';
import 'package:dayseven/features/world/domain/dayseven_3d_model.dart';
import 'package:dayseven/shared/kb/bundle.dart';
import 'package:dayseven/shared/ui/dialog.dart';
import 'package:dayseven/shared/ui/theme.dart';

/// Opens the landmark dialog to add a new pin or edit an [existing] landmark.
Future<void> showLandmarkDialog({
  required BuildContext context,
  required WorldController controller,
  double? initialLatitude,
  double? initialLongitude,
  Model3DLandmark? existing,
}) async {
  final colors = context.ds;
  final nameController = TextEditingController(text: existing?.name ?? '');
  final latController = TextEditingController(
    text: existing != null
        ? existing.latitude.toStringAsFixed(2)
        : (initialLatitude != null
            ? initialLatitude.toStringAsFixed(2)
            : '0.0'),
  );
  final lonController = TextEditingController(
    text: existing != null
        ? existing.longitude.toStringAsFixed(2)
        : (initialLongitude != null
            ? initialLongitude.toStringAsFixed(2)
            : '0.0'),
  );
  final docController = TextEditingController(text: existing?.document ?? '');
  final descController = TextEditingController(
    text: existing?.description ?? '',
  );

  String selectedCategory = existing?.category ?? 'landmark';
  String? nameError;
  String? latError;
  String? lonError;

  final isEdit = existing != null;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => DsDialog(
        title: Text(
          isEdit ? 'Edit Landmark Pin' : 'Add Landmark Pin',
          style: uiTextStyle(size: 16, weight: 600, color: colors.text),
        ),
        actions: [
          DsDialogAction(
            label: 'Cancel',
            onPressed: () => Navigator.of(dialogContext).pop(),
            tone: DsDialogActionTone.muted,
          ),
          if (isEdit)
            DsDialogAction(
              key: const Key('landmark-dialog-delete-button'),
              label: 'Delete',
              tone: DsDialogActionTone.danger,
              onPressed: () {
                controller.removeLandmark(existing.id);
                Navigator.of(dialogContext).pop();
              },
            ),
          DsDialogAction(
            key: const Key('landmark-dialog-save-button'),
            label: 'Save',
            tone: DsDialogActionTone.normal,
            onPressed: () {
              final name = nameController.text.trim();
              final latText = latController.text.trim();
              final lonText = lonController.text.trim();
              final lat = double.tryParse(latText);
              final lon = double.tryParse(lonText);

              setDialogState(() {
                nameError = name.isEmpty ? 'Name is required' : null;
                latError = (lat == null || lat < -90.0 || lat > 90.0)
                    ? 'Latitude must be between -90 and 90'
                    : null;
                lonError = (lon == null || lon < -180.0 || lon > 180.0)
                    ? 'Longitude must be between -180 and 180'
                    : null;
              });

              if (nameError == null && latError == null && lonError == null) {
                final doc = docController.text.trim();
                final desc = descController.text.trim();

                if (isEdit) {
                  controller.updateLandmark(
                    existing.copyWith(
                      name: name,
                      latitude: lat!,
                      longitude: lon!,
                      category: selectedCategory,
                      document: doc.isEmpty ? null : doc,
                      description: desc.isEmpty ? null : desc,
                    ),
                  );
                } else {
                  controller.addLandmark(
                    Model3DLandmark(
                      id: newId(),
                      name: name,
                      latitude: lat!,
                      longitude: lon!,
                      category: selectedCategory,
                      document: doc.isEmpty ? null : doc,
                      description: desc.isEmpty ? null : desc,
                    ),
                  );
                }
                Navigator.of(dialogContext).pop();
              }
            },
          ),
        ],
        children: [
          TextField(
            key: const Key('landmark-name-input'),
            controller: nameController,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Name',
              errorText: nameError,
            ),
          ),
          const SizedBox(height: DsSpace.sm),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('landmark-lat-input'),
                  controller: latController,
                  decoration: InputDecoration(
                    labelText: 'Latitude (-90 to 90)',
                    errorText: latError,
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: DsSpace.sm),
              Expanded(
                child: TextField(
                  key: const Key('landmark-lon-input'),
                  controller: lonController,
                  decoration: InputDecoration(
                    labelText: 'Longitude (-180 to 180)',
                    errorText: lonError,
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: DsSpace.sm),
          DropdownButtonFormField<String>(
            key: const Key('landmark-category-select'),
            initialValue: selectedCategory,
            decoration: const InputDecoration(labelText: 'Category'),
            dropdownColor: colors.cardSurface,
            items: const [
              DropdownMenuItem(value: 'landmark', child: Text('Landmark')),
              DropdownMenuItem(value: 'city', child: Text('City')),
              DropdownMenuItem(value: 'mountain', child: Text('Mountain')),
              DropdownMenuItem(value: 'ruin', child: Text('Ruin')),
              DropdownMenuItem(value: 'port', child: Text('Port')),
            ],
            onChanged: (val) {
              if (val != null) {
                setDialogState(() => selectedCategory = val);
              }
            },
          ),
          const SizedBox(height: DsSpace.sm),
          TextField(
            key: const Key('landmark-doc-input'),
            controller: docController,
            decoration: const InputDecoration(
              labelText: 'Linked Document (e.g. Places/Oakhaven.md)',
            ),
          ),
          const SizedBox(height: DsSpace.sm),
          TextField(
            key: const Key('landmark-desc-input'),
            controller: descController,
            decoration: const InputDecoration(
              labelText: 'Description (optional)',
            ),
            maxLines: 2,
          ),
        ],
      ),
    ),
  );
}
