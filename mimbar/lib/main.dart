import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/store.dart';
import 'services/fliers.dart';
import 'services/native.dart';
import 'services/notifications.dart';
import 'services/sync.dart';
import 'ui/attach_flier_screen.dart';
import 'ui/event_form_screen.dart';
import 'ui/shell.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Notifs.init(onTap: openEventById);
  await Fliers.init();
  await store.init();
  await sync.init();
  runApp(const MimbarApp());
  await Notifs.requestPermission();
  final launchId = await Notifs.launchEventId();
  if (launchId != null) {
    WidgetsBinding.instance
        .addPostFrameCallback((_) => openEventById(launchId));
  }
  // An image shared into Mimbar (e.g. a flier from WhatsApp).
  NativeBridge.onSharedImage(openAttachFlier);
  final shared = await NativeBridge.takeSharedImage();
  if (shared != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) => openAttachFlier(shared));
  }
}

void openAttachFlier(String path) => navigatorKey.currentState?.push(
    MaterialPageRoute(builder: (_) => AttachFlierScreen(imagePath: path)));

void openEventById(int id) {
  final e = store.eventById(id);
  if (e == null) return;
  navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => EventFormScreen(existing: e)));
}

const ink = Color(0xFF111111);
const canvas = Colors.white;

/// Light grey for text fields and inset panels on the white canvas.
const fieldFill = Color(0xFFF2F2F7);
const hairline = Color(0x1A000000);

/// Monochrome, restrained theme: colour is reserved for meaning (the event
/// type strips), hierarchy comes from weight, size and spacing.
ThemeData buildTheme(bool ur) {
  final scheme = ColorScheme.fromSeed(
    seedColor: ink,
    dynamicSchemeVariant: DynamicSchemeVariant.monochrome,
  ).copyWith(
    primary: ink,
    onPrimary: Colors.white,
    primaryContainer: const Color(0xFFE8E8ED),
    onPrimaryContainer: ink,
    surface: Colors.white,
    onSurface: ink,
    onSurfaceVariant: const Color(0xFF6E6E73),
    outlineVariant: hairline,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: canvas,
    fontFamily: ur ? 'Nastaliq' : null,
  );

  // Large Latin text reads better slightly tightened; Urdu is a connected
  // script and must never be letter-spaced, but needs taller lines.
  TextStyle? t(TextStyle? s, {double track = 0, FontWeight? w}) => s?.copyWith(
        letterSpacing: ur ? 0 : track,
        fontWeight: w ?? s.fontWeight,
        height: ur ? (s.height ?? 1.2) + 0.35 : s.height,
      );
  final tt = base.textTheme;
  final textTheme = tt.copyWith(
    displaySmall: t(tt.displaySmall, track: -0.8, w: FontWeight.w700),
    headlineMedium: t(tt.headlineMedium, track: -0.6, w: FontWeight.w700),
    headlineSmall: t(tt.headlineSmall, track: -0.5, w: FontWeight.w700),
    titleLarge: t(tt.titleLarge, track: -0.4, w: FontWeight.w700),
    titleMedium: t(tt.titleMedium, track: -0.2, w: FontWeight.w600),
    titleSmall: t(tt.titleSmall, w: FontWeight.w600),
    bodyLarge: t(tt.bodyLarge),
    bodyMedium: t(tt.bodyMedium),
    bodySmall: t(tt.bodySmall, track: ur ? 0 : 0.1),
    labelLarge: t(tt.labelLarge, w: FontWeight.w600),
    labelMedium: t(tt.labelMedium),
    labelSmall: t(tt.labelSmall, track: ur ? 0 : 0.2),
  );

  final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
  return base.copyWith(
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: canvas,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      foregroundColor: ink,
      titleTextStyle: textTheme.titleLarge!.copyWith(color: ink),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: hairline),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white.withValues(alpha: 0.78),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      indicatorColor: const Color(0xFFE8E8ED),
      labelTextStyle: WidgetStatePropertyAll(textTheme.labelSmall),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: ink,
      foregroundColor: Colors.white,
      elevation: 2,
      highlightElevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: ink,
        foregroundColor: Colors.white,
        shape: rounded,
        textStyle: textTheme.labelLarge,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? ink : Colors.white),
        foregroundColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? Colors.white : ink),
        side: const WidgetStatePropertyAll(BorderSide(color: hairline)),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white,
      selectedColor: const Color(0xFFE8E8ED),
      side: const BorderSide(color: hairline),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: fieldFill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: ink, width: 1.4),
      ),
    ),
    dividerTheme: const DividerThemeData(color: hairline, space: 1),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: ink,
      shape: rounded,
    ),
  );
}

class MimbarApp extends StatelessWidget {
  const MimbarApp({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final ur = store.ur;
          return MaterialApp(
            navigatorKey: navigatorKey,
            debugShowCheckedModeBanner: false,
            title: 'Mimbar',
            locale: Locale(store.settings.lang),
            supportedLocales: const [Locale('en'), Locale('ur')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: buildTheme(ur),
            home: const Shell(),
          );
        },
      );
}
