/// Sorting never changes the persisted recent-file order.
enum RecentSort {
  recent,
  modifiedNewest,
  modifiedOldest,
  titleAscending,
  titleDescending,
}

String decodeRecentText(Object? value) {
  final text = value?.toString() ?? '';
  try {
    return Uri.decodeComponent(text);
  } on FormatException {
    return text;
  } on ArgumentError {
    return text;
  }
}

List<Map<String, dynamic>> selectRecentFiles(
  Iterable<Map> recent, {
  String query = '',
  String? backendId,
  RecentSort sort = RecentSort.recent,
}) {
  final needle = query.trim().toLowerCase();
  final indexed = <({int index, Map<String, dynamic> entry})>[];
  var index = 0;
  for (final raw in recent) {
    final entry = Map<String, dynamic>.from(raw);
    final current = index++;
    if (backendId != null && (entry['backendId'] ?? 'local') != backendId)
      continue;
    final refs = entry['pdfReferences'];
    final folder = entry['readablePath'];
    final name = entry['readableName'] ?? entry['name'];
    final readableFile = folder is String && name is String
        ? '${folder.endsWith('/') ? folder : '$folder/'}$name'
        : null;
    final values = <Object?>[
      entry['name'],
      entry['path'],
      entry['readablePath'],
      entry['readableName'],
      readableFile,
      if (readableFile != null && !readableFile.toLowerCase().endsWith('.xopp'))
        '$readableFile.xopp',
      if (refs is List) ...refs,
    ];
    if (needle.isNotEmpty &&
        !values.any(
          (value) => decodeRecentText(value).toLowerCase().contains(needle),
        ))
      continue;
    indexed.add((index: current, entry: entry));
  }
  DateTime? date(Object? value) =>
      value == null ? null : DateTime.tryParse(value.toString());
  indexed.sort((a, b) {
    var result = 0;
    switch (sort) {
      case RecentSort.recent:
        break;
      case RecentSort.titleAscending:
      case RecentSort.titleDescending:
        result = decodeRecentText(a.entry['name']).toLowerCase().compareTo(
          decodeRecentText(b.entry['name']).toLowerCase(),
        );
        if (sort == RecentSort.titleDescending) result = -result;
      case RecentSort.modifiedNewest:
      case RecentSort.modifiedOldest:
        final x = date(a.entry['modified']);
        final y = date(b.entry['modified']);
        if (x == null || y == null) {
          result = x == null ? (y == null ? 0 : 1) : -1;
        } else {
          result = x.compareTo(y);
          if (sort == RecentSort.modifiedNewest) result = -result;
        }
    }
    return result == 0 ? a.index.compareTo(b.index) : result;
  });
  return indexed.map((item) => item.entry).toList();
}
