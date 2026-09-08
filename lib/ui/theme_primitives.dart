import 'package:flutter/material.dart';

abstract final class MenoTheme {
  static const paper = Color(0xFFFFFCF5);
  static const appBackground = Color(0xFFF7F6F1);
  static const binderBackground = Color(0xFFF1EEE6);
  static const ink = Color(0xFF262923);
  static const serif = 'Georgia';

  static const saveDebounce = Duration(milliseconds: 700);
  static const quickAnimation = Duration(milliseconds: 180);
}

@immutable
class MenoSurfaces extends ThemeExtension<MenoSurfaces> {
  const MenoSurfaces({
    required this.page,
    required this.paper,
    required this.elevated,
    required this.glassMode,
  });

  const MenoSurfaces.opaque()
    : page = MenoTheme.appBackground,
      paper = MenoTheme.paper,
      elevated = MenoTheme.paper,
      glassMode = false;

  const MenoSurfaces.glass()
    : page = const Color(0xA3F7F6F1),
      paper = const Color(0xB8FFFCF5),
      elevated = const Color(0xDBFFFCF5),
      glassMode = true;

  final Color page;
  final Color paper;
  final Color elevated;
  final bool glassMode;

  static MenoSurfaces of(BuildContext context) =>
      Theme.of(context).extension<MenoSurfaces>() ??
      const MenoSurfaces.opaque();

  @override
  MenoSurfaces copyWith({
    Color? page,
    Color? paper,
    Color? elevated,
    bool? glassMode,
  }) => MenoSurfaces(
    page: page ?? this.page,
    paper: paper ?? this.paper,
    elevated: elevated ?? this.elevated,
    glassMode: glassMode ?? this.glassMode,
  );

  @override
  MenoSurfaces lerp(covariant MenoSurfaces? other, double t) {
    if (other == null) return this;
    return MenoSurfaces(
      page: Color.lerp(page, other.page, t)!,
      paper: Color.lerp(paper, other.paper, t)!,
      elevated: Color.lerp(elevated, other.elevated, t)!,
      glassMode: t < .5 ? glassMode : other.glassMode,
    );
  }
}
