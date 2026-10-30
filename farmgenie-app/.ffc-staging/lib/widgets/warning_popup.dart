import 'package:flutter/material.dart';

import 'geofence_warning_dialog.dart';

/// Serializes warnings per navigator so concurrent failures cannot stack dialogs.
class WarningPopup {
  static final _queues = Expando<_WarningQueue>();

  /// Runs [present] once earlier warnings have closed, so other dialogs (such
  /// as the location settings prompt) never stack on top of a warning.
  static Future<T?> enqueue<T>(
    BuildContext context,
    Future<T?> Function() present,
  ) {
    final navigator = Navigator.of(context, rootNavigator: true);
    final queue = _queues[navigator] ??= _WarningQueue();
    final result = queue.tail.then((_) async {
      // Also safe for errors reported during initState or a state update.
      WidgetsBinding.instance.scheduleFrame();
      await WidgetsBinding.instance.endOfFrame;
      if (!context.mounted || !navigator.mounted) return null;
      return present();
    });
    queue.tail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  static Future<void> show(BuildContext context, String message) {
    if (!context.mounted || message.trim().isEmpty) return Future.value();
    final navigator = Navigator.of(context, rootNavigator: true);
    final queue = _queues[navigator] ??= _WarningQueue();
    final pending = queue.pending[message];
    if (pending != null) return pending;
    final result = enqueue<void>(context, () async {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) =>
            GeofenceWarningDialog.matchesMessage(message)
            ? GeofenceWarningDialog(message: message)
            : AlertDialog(
                scrollable: true,
                icon: const Icon(Icons.warning_amber_rounded),
                title: const Text('Warning'),
                content: Text(message),
                actions: [
                  FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('OK'),
                  ),
                ],
              ),
      );
    });
    final completed = result.whenComplete(() {
      queue.pending.remove(message);
    });
    queue.pending[message] = completed;
    return completed;
  }
}

class _WarningQueue {
  Future<void> tail = Future.value();
  final pending = <String, Future<void>>{};
}

/// Keeps existing error/retry state while presenting each reported warning.
mixin WarningPopupState<T extends StatefulWidget> on State<T> {
  String? _warningMessage;

  String? get warningMessage => _warningMessage;

  set warningMessage(String? message) {
    _warningMessage = message;
    if (mounted && message != null) WarningPopup.show(context, message);
  }
}
