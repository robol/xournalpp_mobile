import 'XppPage.dart';

/// Prefix sums of page aspect ratios. Zoom and viewport changes only change
/// the multiplier; document structure/size changes explicitly invalidate this.
class PageGeometry {
  PageGeometry(List<XppPage> pages) {
    for (var i = 0; i < pages.length; i++) {
      _indices[pages[i]] = i;
      _ratios.add(_ratios.last + 1 / pages[i].pageSize!.ratio);
    }
  }
  final _ratios = <double>[0];
  final _indices = <XppPage, int>{};
  int indexOf(XppPage page) => _indices[page] ?? -1;
  double offset(int index, double displayWidth, double gap, double firstTop) =>
      firstTop + _ratios[index] * displayWidth + index * gap;
  int pageAt(double y, double displayWidth, double gap, double firstTop) {
    var low = 0;
    var high = _ratios.length - 2;
    while (low < high) {
      final middle = (low + high + 1) ~/ 2;
      if (offset(middle, displayWidth, gap, firstTop) <= y) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return low;
  }
}
