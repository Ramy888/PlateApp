import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models.dart';
import '../ui/check_screen.dart';
import 'providers.dart';

/// Saving a patch, from wherever it was suggested.
///
/// The manual flow, a chat reply and a spoken one all produce the same thing —
/// a meal and one addition — so they all save the same way and land in the same
/// list. A history that only remembered the patches you reached one particular
/// way would be a filing decision nobody asked for.
Future<void> savePatch(
  BuildContext context,
  WidgetRef ref, {
  required MealSlot slot,
  required List<String> foodIds,
  required Addition addition,
  List<String> gapIds = const [],
  bool returnToStart = true,
}) async {
  final saved = SavedPatch(
    id: DateTime.now().microsecondsSinceEpoch.toString(),
    savedAt: DateTime.now(),
    slot: slot,
    foodIds: foodIds,
    additionId: addition.id,
    additionName: addition.name,
    additionEmoji: addition.emoji,
    gapIds: gapIds,
  );
  await ref.read(historyProvider.notifier).save(saved);
  if (!context.mounted) return;

  // The after-meal check is the other half of saving: it is what makes the
  // history worth keeping rather than a list of things you once tapped.
  await Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => CheckScreen(patchId: saved.id)),
  );
  if (!context.mounted) return;

  ref.read(mealDraftProvider.notifier).reset();
  if (returnToStart) {
    // Back to a clean plate: the meal has been dealt with.
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
}
