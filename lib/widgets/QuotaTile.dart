import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class QuotaTile extends StatefulWidget {
  @override
  _QuotaTileState createState() => _QuotaTileState();
}

class _QuotaTileState extends State<QuotaTile> {
  @override
  Widget build(BuildContext context) {
    if (kIsWeb ||
        [
          TargetPlatform.android,
          TargetPlatform.iOS,
        ].contains(Theme.of(context).platform))
      return SizedBox.shrink();
    else
      return Container();
  }
}
