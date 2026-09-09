import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meno/ui/theme_primitives.dart';

void main() {
  test('glass surfaces use balanced paper translucency', () {
    const surfaces = MenoSurfaces.glass();

    expect(surfaces.page, const Color(0x26F7F6F1));
    expect(surfaces.paper, const Color(0x4DFFFCF5));
    expect(surfaces.elevated, const Color(0x8CFFFCF5));
    expect(surfaces.glassMode, isTrue);
  });

  test('opaque surfaces retain the original palette', () {
    const surfaces = MenoSurfaces.opaque();

    expect(surfaces.page, MenoTheme.appBackground);
    expect(surfaces.paper, MenoTheme.paper);
    expect(surfaces.elevated, MenoTheme.paper);
    expect(surfaces.glassMode, isFalse);
  });
}
