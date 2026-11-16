import 'package:material_ui/material_ui.dart';

/// Palette del brand, dallo stile del mockup approvato (A1): blu notte, arancio
/// energico e blu elettrico, con vetro e bagliori.
abstract final class AppColors {
  // Accenti del brand.
  static const Color brandOrange = Color(0xFFFF7A1A);
  static const Color brandOrangeLight = Color(0xFFFFA24C);
  static const Color brandOrangeDeep = Color(0xFFE85A00);
  static const Color brandBlue = Color(0xFF2F7BFF);
  static const Color brandCyan = Color(0xFF22D3EE);

  // Colori delle sezioni (stessi nomi usati dalle schermate).
  static const Color brandViolet = Color(0xFF8B5CF6);
  static const Color brandMint = Color(0xFF2EE6A6);
  static const Color brandCoral = Color(0xFFFF4D6D);
  static const Color brandAmber = Color(0xFFFFC46B);

  static const Color darkBackground = Color(0xFF060A14);
  static const Color darkSurface = Color(0xFF111A2E);
  static const Color darkSurfaceHigh = Color(0xFF1A2540);
  static const Color darkOutline = Color(0xFF26324F);
  static const Color darkTextSecondary = Color(0xFF97A3C2);

  static const Color lightBackground = Color(0xFFF3F5FB);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceHigh = Color(0xFFEDF1F9);
  static const Color lightOutline = Color(0xFFDDE3F0);
  static const Color lightTextSecondary = Color(0xFF56627F);

  /// Gradiente del marchio «N»: blu elettrico → arancio, come nel logo del mockup.
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brandBlue, Color(0xFF7A5CFF), brandOrange],
    stops: [0, 0.5, 1],
  );

  /// Gradiente del pulsante centrale «Scambia».
  static const LinearGradient orangeGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brandOrangeLight, brandOrange, brandOrangeDeep],
  );

  /// Gradiente acceso derivato da un colore di sezione.
  static LinearGradient accentGradient(Color accent) => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color.lerp(accent, Colors.white, 0.18)!,
      accent,
      Color.lerp(accent, const Color(0xFF0B1022), 0.35)!,
    ],
    stops: const [0, 0.55, 1],
  );
}

abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;

  /// Margine delle schermate; il fondo lascia spazio alla barra di navigazione.
  static const EdgeInsets pagePadding = EdgeInsets.fromLTRB(18, 8, 18, 132);
}

abstract final class AppTheme {
  static ThemeData get dark => _build(Brightness.dark);
  static ThemeData get light => _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;
    final ColorScheme base = ColorScheme.fromSeed(
      seedColor: AppColors.brandOrange,
      brightness: brightness,
    );
    final ColorScheme scheme = base.copyWith(
      primary: isDark ? AppColors.brandOrange : const Color(0xFFD9530A),
      onPrimary: Colors.white,
      secondary: isDark ? AppColors.brandMint : const Color(0xFF047857),
      onSecondary: isDark ? const Color(0xFF002117) : Colors.white,
      tertiary: isDark ? AppColors.brandBlue : const Color(0xFF1D4ED8),
      onTertiary: Colors.white,
      error: isDark ? const Color(0xFFFF6B81) : const Color(0xFFC81E3A),
      surface: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      onSurface: isDark ? const Color(0xFFF4F6FF) : const Color(0xFF0F172A),
      onSurfaceVariant: isDark
          ? AppColors.darkTextSecondary
          : AppColors.lightTextSecondary,
      surfaceContainerHighest: isDark
          ? AppColors.darkSurfaceHigh
          : AppColors.lightSurfaceHigh,
      outline: isDark ? AppColors.darkOutline : AppColors.lightOutline,
    );

    final BorderRadius radius = BorderRadius.circular(26);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark
          ? AppColors.darkBackground
          : AppColors.lightBackground,
      textTheme: _textTheme(scheme),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      // Card «in vetro»: superficie semitrasparente con bordo luminoso.
      cardTheme: CardThemeData(
        color: isDark
            ? AppColors.darkSurface.withValues(alpha: 0.78)
            : Colors.white.withValues(alpha: 0.92),
        elevation: 0,
        margin: EdgeInsets.zero,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : AppColors.lightOutline,
          ),
        ),
      ),
      // Menu «⋯» e ordinamenti: bianchi, arrotondati, ombra leggera (Fase 5, Blocco 5).
      popupMenuTheme: PopupMenuThemeData(
        color: isDark ? AppColors.darkSurface : Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shadowColor: Colors.black.withValues(alpha: 0.25),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.08) : AppColors.lightOutline,
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        height: 82,
        // L'evidenziazione è disegnata dalle icone stesse (pillola o cerchio arancio).
        indicatorColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>((states) {
          final bool selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            letterSpacing: 0.1,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData>((states) {
          final bool selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
            size: 24,
          );
        }),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
        selectedColor: scheme.primary.withValues(alpha: isDark ? 0.24 : 0.14),
        checkmarkColor: scheme.primary,
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.8)),
        labelStyle: TextStyle(
          color: scheme.onSurface,
          fontWeight: FontWeight.w700,
          fontSize: 12.5,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outline.withValues(alpha: isDark ? 0.55 : 0.7),
        thickness: 1,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.primary,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 15.5,
          fontWeight: FontWeight.w700,
        ),
        subtitleTextStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 13,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          side: BorderSide(color: scheme.outline),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: scheme.onSurfaceVariant.withValues(alpha: 0.5),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.surfaceContainerHighest,
        contentTextStyle: TextStyle(color: scheme.onSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  static TextTheme _textTheme(ColorScheme scheme) {
    final TextTheme base = ThemeData(brightness: scheme.brightness).textTheme;
    return base
        .copyWith(
          headlineMedium: base.headlineMedium?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: -1,
          ),
          headlineSmall: base.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: -0.8,
          ),
          titleLarge: base.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
          titleMedium: base.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
          titleSmall: base.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.1,
          ),
          bodyMedium: base.bodyMedium?.copyWith(height: 1.45),
          bodySmall: base.bodySmall?.copyWith(height: 1.4),
          labelLarge: base.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        )
        .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
  }
}
