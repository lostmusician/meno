import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'providers/journal_providers.dart';
import 'ui/editor_screen.dart';
import 'ui/theme_primitives.dart';

final _navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isMacOS) {
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
  }
  runApp(const ProviderScope(child: MenoApp()));
}

class MenoApp extends ConsumerStatefulWidget {
  const MenoApp({super.key});

  @override
  ConsumerState<MenoApp> createState() => _MenoAppState();
}

class _MenoAppState extends ConsumerState<MenoApp> with WindowListener {
  bool _closing = false;
  late final ProviderSubscription<bool> _glassModeSubscription;

  @override
  void initState() {
    super.initState();
    if (Platform.isMacOS) windowManager.addListener(this);
    _glassModeSubscription = ref.listenManual<bool>(
      journalControllerProvider.select((state) => state.glassModeEnabled),
      (_, enabled) => unawaited(
        ref.read(windowAppearanceServiceProvider).setGlassMode(enabled),
      ),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _glassModeSubscription.close();
    if (Platform.isMacOS) windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() async {
    if (_closing) return;
    final saved = await ref.read(saveCoordinatorProvider.notifier).flushAll();
    if (saved) {
      _closing = true;
      await windowManager.destroy();
      return;
    }
    final context = _navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Meno could not save'),
        content: const Text(
          'Your unsaved writing is still visible. Retry before closing, or '
          'create an emergency backup of everything already saved.',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final location = await getSaveLocation(
                suggestedName: 'Meno Emergency.meno-backup',
                acceptedTypeGroups: const [
                  XTypeGroup(label: 'Meno backup', extensions: ['meno-backup']),
                ],
              );
              if (location != null) {
                await ref
                    .read(backupServiceProvider)
                    .createBackup(File(location.path));
              }
            },
            child: const Text('Emergency backup'),
          ),
          TextButton(
            onPressed: () async {
              _closing = true;
              Navigator.pop(dialogContext);
              await windowManager.destroy();
            },
            child: const Text('Quit anyway'),
          ),
          FilledButton(
            onPressed: () async {
              final retry = await ref
                  .read(saveCoordinatorProvider.notifier)
                  .flushAll();
              if (retry && dialogContext.mounted) {
                _closing = true;
                Navigator.pop(dialogContext);
                await windowManager.destroy();
              }
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final windowAppearance = ref.watch(windowAppearanceServiceProvider);
    final glassMode =
        windowAppearance.isSupported &&
        ref.watch(
          journalControllerProvider.select((state) => state.glassModeEnabled),
        );
    final surfaces = glassMode
        ? const MenoSurfaces.glass()
        : const MenoSurfaces.opaque();
    final baseColorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFAAB6A8),
      brightness: glassMode ? Brightness.dark : Brightness.light,
    );
    final colorScheme = glassMode
        ? baseColorScheme.copyWith(
            surface: surfaces.elevated,
            onSurface: MenoTheme.glassInk,
            onSurfaceVariant: MenoTheme.glassMutedInk,
          )
        : baseColorScheme.copyWith(surface: surfaces.elevated);
    final foregroundColor = glassMode ? MenoTheme.glassInk : MenoTheme.ink;
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Meno',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: surfaces.page,
        canvasColor: surfaces.paper,
        colorScheme: colorScheme,
        dialogTheme: DialogThemeData(backgroundColor: surfaces.elevated),
        bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: surfaces.elevated,
          modalBackgroundColor: surfaces.elevated,
        ),
        extensions: [surfaces],
        textTheme:
            ThemeData(
              brightness: glassMode ? Brightness.dark : Brightness.light,
            ).textTheme.apply(
              bodyColor: foregroundColor,
              displayColor: foregroundColor,
              fontFamily: MenoTheme.serif,
            ),
      ),
      home: const EditorScreen(),
    );
  }
}
