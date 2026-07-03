import 'package:flutter/material.dart';
import 'package:xournalpp/generated/l10n.dart';

Future<T> runWithLoadingFileDialog<T>(
  BuildContext context,
  Future<T> Function() task,
) async {
  var dialogShown = false;
  void showLoading() {
    if (!context.mounted || dialogShown) return;
    dialogShown = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 24),
              Expanded(child: Text(S.of(context).loadingFile)),
            ],
          ),
        ),
      ),
    );
  }

  showLoading();
  await WidgetsBinding.instance.endOfFrame;
  try {
    return await task();
  } finally {
    if (dialogShown && context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }
}
