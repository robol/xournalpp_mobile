import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:xournalpp/generated/l10n.dart';

class WorkspaceActions extends StatelessWidget {
  final VoidCallback onNew, onOpen, onImport;
  const WorkspaceActions({
    super.key,
    required this.onNew,
    required this.onOpen,
    required this.onImport,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final actions = [
        QuickActionCard(
          label: S.of(context).newNotebook,
          icon: Icons.note_add_outlined,
          accent: Theme.of(context).colorScheme.primary,
          onTap: onNew,
          primary: true,
        ),
        QuickActionCard(
          label: S.of(context).workspaceOpen,
          icon: Icons.folder_open_outlined,
          accent: Theme.of(context).colorScheme.onSurfaceVariant,
          onTap: onOpen,
        ),
        QuickActionCard(
          label: S.of(context).importPdf,
          icon: Icons.picture_as_pdf_outlined,
          accent: Theme.of(context).colorScheme.secondary,
          onTap: onImport,
        ),
      ];
      if (constraints.maxWidth <
          600 * MediaQuery.textScalerOf(context).scale(14) / 14) {
        return Column(
          children: [
            for (final action in actions)
              Padding(padding: const EdgeInsets.only(bottom: 8), child: action),
          ],
        );
      }
      return Row(
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) const SizedBox(width: 16),
            Expanded(child: actions[i]),
          ],
        ],
      );
    },
  );
}

class QuickActionCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;
  final bool primary;
  const QuickActionCard({
    super.key,
    required this.label,
    required this.icon,
    required this.accent,
    required this.onTap,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: primary
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.surfaceContainer,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(
        color: primary
            ? accent.withValues(alpha: .55)
            : Theme.of(context).colorScheme.outlineVariant,
      ),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(icon, color: accent, size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class DocumentCard extends StatelessWidget {
  final String name, path, modified;
  final String? preview;
  final VoidCallback onOpen, onLongPress;
  const DocumentCard({
    super.key,
    required this.name,
    required this.path,
    required this.modified,
    this.preview,
    required this.onOpen,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
    borderRadius: BorderRadius.circular(16),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onOpen,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Center(
                child: NotebookCover(name: name, preview: preview),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              modified,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  name.toLowerCase().endsWith('.pdf') ? 'PDF' : 'XOPP',
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    letterSpacing: 1.5,
                  ),
                ),
                const Spacer(),
                Tooltip(
                  message: path,
                  child: Icon(
                    Icons.info_outline,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class NotebookCover extends StatelessWidget {
  final String name;
  final String? preview;
  const NotebookCover({super.key, required this.name, this.preview});

  @override
  Widget build(BuildContext context) {
    // Explicit hash keeps cover colors stable across processes and platforms.
    var hash = 0;
    for (final unit in name.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    const colors = [
      Color(0xff437b91),
      Color(0xff876478),
      Color(0xff5d8178),
      Color(0xff8d785b),
      Color(0xff686c91),
    ];
    final color = colors[hash % colors.length];
    Uint8List? bytes;
    try {
      if (preview != null && preview!.isNotEmpty)
        bytes = base64Decode(preview!);
    } on FormatException {
      /* Older recents may not contain a usable preview. */
    }
    final fallback = Center(
      child: Icon(
        name.toLowerCase().endsWith('.pdf')
            ? Icons.picture_as_pdf_outlined
            : Icons.menu_book_rounded,
        color: Colors.white70,
        size: 44,
      ),
    );
    return AspectRatio(
      aspectRatio: .8,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 8,
              offset: Offset(3, 5),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            Container(width: 9, color: Colors.black.withValues(alpha: .22)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: bytes == null
                    ? fallback
                    : Image.memory(
                        bytes,
                        fit: BoxFit.contain,
                        excludeFromSemantics: true,
                        errorBuilder: (_, __, ___) => fallback,
                      ),
              ),
            ),
            Container(
              width: 3,
              margin: const EdgeInsets.symmetric(vertical: 7),
              color: Colors.white54,
            ),
          ],
        ),
      ),
    );
  }
}

class EmptyDocumentsState extends StatelessWidget {
  final VoidCallback onNew;
  const EmptyDocumentsState({super.key, required this.onNew});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
    child: Column(
      children: [
        const SizedBox(
          height: 110,
          width: 88,
          child: NotebookCover(name: 'Workspace'),
        ),
        const SizedBox(height: 24),
        Text(
          S.of(context).workspaceEmptyTitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Text(
            S.of(context).workspaceEmptyDescription,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: onNew,
          icon: const Icon(Icons.add),
          label: Text(S.of(context).workspaceCreate),
        ),
      ],
    ),
  );
}
