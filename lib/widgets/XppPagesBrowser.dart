import 'package:flutter/material.dart';
import 'package:xournalpp/generated/l10n.dart';

class XppPagesBrowser extends StatelessWidget {
  final int currentPage;
  final int pageCount;
  final ValueChanged<int>? onPageChange;
  final VoidCallback? onPageAdd;
  final VoidCallback? onPageDelete;

  const XppPagesBrowser({
    Key? key,
    required this.currentPage,
    required this.pageCount,
    this.onPageChange,
    this.onPageAdd,
    this.onPageDelete,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final canGoBack = currentPage > 0;
    final canGoForward = currentPage < pageCount - 1;
    final canDelete = pageCount > 0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: S.of(context).movePage,
          onPressed: canGoBack
              ? () => onPageChange?.call(currentPage - 1)
              : null,
        ),
        SizedBox(
          width: 120,
          child: Text(
            '${currentPage + 1} / $pageCount',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: S.of(context).movePage,
          onPressed: canGoForward
              ? () => onPageChange?.call(currentPage + 1)
              : null,
        ),
        const SizedBox(width: 12),
        IconButton(
          icon: const Icon(Icons.add),
          tooltip: S.of(context).addPage,
          onPressed: onPageAdd,
        ),
        IconButton(
          icon: const Icon(Icons.delete_forever),
          tooltip: S.of(context).deletePage,
          onPressed: canDelete ? onPageDelete : null,
        ),
      ],
    );
  }
}
