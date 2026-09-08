import 'package:flutter/material.dart';

/// Approved Meno artwork prepared from the original supplied brand masters.
abstract final class MenoBrandAssets {
  static const mark = 'assets/brand/meno-mark-sage.png';
  static const wordmark = 'assets/brand/meno-wordmark-sage.png';
}

class MenoBrandMark extends StatelessWidget {
  const MenoBrandMark({this.size = 32, super.key});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: Image.asset(
      MenoBrandAssets.mark,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: 'Meno',
    ),
  );
}

class MenoWordmark extends StatelessWidget {
  const MenoWordmark({this.width = 120, super.key});

  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: width * 26 / 66,
    child: Image.asset(
      MenoBrandAssets.wordmark,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: 'Meno',
    ),
  );
}
