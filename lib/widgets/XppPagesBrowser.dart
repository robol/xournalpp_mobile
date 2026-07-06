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
          child: TextButton(
            onPressed: pageCount > 0
                ? () => _showJumpToPageDialog(context)
                : null,
            child: Text(
              '${currentPage + 1} / $pageCount',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
              ),
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

  Future<void> _showJumpToPageDialog(BuildContext context) async {
    final page = await showDialog<int>(
      context: context,
      builder: (context) =>
          _JumpToPageDialog(initialPage: currentPage, pageCount: pageCount),
    );

    if (page == null || page == currentPage) return;
    onPageChange?.call(page);
  }
}

class _JumpToPageDialog extends StatefulWidget {
  const _JumpToPageDialog({required this.initialPage, required this.pageCount});

  final int initialPage;
  final int pageCount;

  @override
  State<_JumpToPageDialog> createState() => _JumpToPageDialogState();
}

class _JumpToPageDialogState extends State<_JumpToPageDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.initialPage + 1}');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(S.of(context).movePage),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: S.of(context).newPageIndex,
            hintText: '1 - ${widget.pageCount}',
          ),
          validator: _validatePage,
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(S.of(context).cancel),
        ),
        TextButton(onPressed: _submit, child: Text(S.of(context).okay)),
      ],
    );
  }

  String? _validatePage(String? value) {
    final page = int.tryParse(value?.trim() ?? '');
    if (page == null || page < 1 || page > widget.pageCount) {
      return '1 - ${widget.pageCount}';
    }
    return null;
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) return;
    Navigator.of(context).pop(int.parse(_controller.text.trim()) - 1);
  }
}
