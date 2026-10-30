import 'package:flutter/material.dart';

/// A provider label remains usable when a backend has no bundled icon.
class StorageProviderLabel extends StatelessWidget {
  const StorageProviderLabel({
    super.key,
    required this.label,
    this.iconAsset,
    this.iconSize = 20,
    this.style,
  });
  final String label;
  final String? iconAsset;
  final double iconSize;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (iconAsset != null) ...[
        Image.asset(
          iconAsset!,
          width: iconSize,
          height: iconSize,
          excludeFromSemantics: true,
          errorBuilder: (_, __, ___) =>
              SizedBox(width: iconSize, height: iconSize),
        ),
        const SizedBox(width: 6),
      ],
      Flexible(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
      ),
    ],
  );
}
