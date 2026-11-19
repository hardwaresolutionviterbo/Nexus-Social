import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// Pezzi comuni della nuova grafica (mockup del titolare, 19/11/2026): viola Piazly e arancio,
/// schede arrotondate, pillole.
abstract final class PiazlyColors {
  static const Color violet = Color(0xFF7C3AED);
  static const Color violetDeep = Color(0xFF5B21B6);
  static const Color violetSoft = Color(0xFFF1EAFE);
  static const Color orangeSoft = Color(0xFFFFEEDF);
  static const Color greenSoft = Color(0xFFE3F8EC);
  static const Color green = Color(0xFF15803D);

  static const LinearGradient violetGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[Color(0xFF8B5CF6), Color(0xFF6D28D9)],
  );
}

/// Una pillola di [PillTabs].
class PillTab<T> {
  const PillTab({required this.value, required this.label, this.icon, this.key});

  final T value;
  final String label;
  final IconData? icon;

  /// Chiave del testo (per i test e per toccare la pillola).
  final Key? key;
}

/// Schede a pillola: quella scelta è arancione piena, le altre bianche con il bordo.
class PillTabs<T> extends StatelessWidget {
  const PillTabs({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onChanged,
    this.padding = const EdgeInsets.fromLTRB(16, 6, 16, 6),
    this.scroll = false,
  });

  final List<PillTab<T>> tabs;
  final T selected;
  final ValueChanged<T> onChanged;
  final EdgeInsetsGeometry padding;

  /// Se le pillole sono tante: scorrono di lato invece di dividersi lo spazio.
  final bool scroll;

  Widget _pill(BuildContext context, PillTab<T> t) {
    final ThemeData theme = Theme.of(context);
    final bool on = t.value == selected;
    final bool dark = theme.brightness == Brightness.dark;
    final Color fg = on ? Colors.white : theme.colorScheme.onSurface;
    return Material(
      color: on ? AppColors.brandOrange : (dark ? AppColors.darkSurface : Colors.white),
      shape: StadiumBorder(
        side: BorderSide(color: on ? AppColors.brandOrange : (dark ? AppColors.darkOutline : AppColors.lightOutline)),
      ),
      elevation: on ? 3 : 0,
      shadowColor: AppColors.brandOrange.withValues(alpha: 0.5),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => onChanged(t.value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (t.icon != null) ...[
                Icon(t.icon, size: 19, color: fg),
                const SizedBox(width: 7),
              ],
              Flexible(
                child: Text(
                  t.label,
                  key: t.key,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(color: fg, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (scroll) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: padding,
        child: Row(
          children: [
            for (int i = 0; i < tabs.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              _pill(context, tabs[i]),
            ],
          ],
        ),
      );
    }
    return Padding(
      padding: padding,
      child: Row(
        children: [
          for (int i = 0; i < tabs.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: _pill(context, tabs[i])),
          ],
        ],
      ),
    );
  }
}

/// Scheda chiara arrotondata, con un leggero bordo; [tint] la colora (es. viola chiaro).
class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.tint,
    this.onTap,
    this.padding = const EdgeInsets.all(14),
    this.margin = const EdgeInsets.fromLTRB(16, 6, 16, 6),
    this.radius = 20,
  });

  final Widget child;
  final Color? tint;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Color bg = tint == null
        ? (dark ? AppColors.darkSurface : Colors.white)
        : (dark ? Color.alphaBlend(tint!.withValues(alpha: 0.18), AppColors.darkSurface) : tint!);
    return Padding(
      padding: margin,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: tint != null
                    ? Colors.transparent
                    : (dark ? AppColors.darkOutline : AppColors.lightOutline),
              ),
              boxShadow: tint != null || dark
                  ? null
                  : <BoxShadow>[
                      BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 14, offset: const Offset(0, 5)),
                    ],
            ),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// Icona in un quadratino arrotondato colorato (menu del profilo, schede).
class IconTile extends StatelessWidget {
  const IconTile(this.icon, {super.key, this.color = PiazlyColors.violet, this.size = 44});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.13),
      borderRadius: BorderRadius.circular(size * 0.3),
    ),
    child: Icon(icon, color: color, size: size * 0.52),
  );
}

/// Riga di menu in una scheda: icona colorata, titolo, descrizione e freccia.
class MenuCard extends StatelessWidget {
  const MenuCard({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.color = PiazlyColors.violet,
    this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color color;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SoftCard(
      onTap: onTap,
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          IconTile(icon, color: color),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                if (subtitle != null)
                  Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          trailing ?? const Icon(Icons.chevron_right_rounded, color: AppColors.brandOrange),
        ],
      ),
    );
  }
}

/// Stato vuoto con un'illustrazione fatta di icone: immagine e video su una nuvola viola.
class PiazlyEmptyArt extends StatelessWidget {
  const PiazlyEmptyArt({super.key, this.front = Icons.image_rounded, this.back = Icons.play_circle_fill_rounded});

  final IconData front;
  final IconData back;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 200,
    height: 130,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 190,
          height: 96,
          decoration: BoxDecoration(
            color: PiazlyColors.violetSoft,
            borderRadius: BorderRadius.circular(60),
          ),
        ),
        Positioned(
          right: 36,
          top: 30,
          child: Transform.rotate(
            angle: 0.18,
            child: Container(
              width: 74,
              height: 58,
              decoration: BoxDecoration(
                color: const Color(0xFFB79CF7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(back, color: Colors.white, size: 30),
            ),
          ),
        ),
        Positioned(
          left: 44,
          top: 16,
          child: Transform.rotate(
            angle: -0.16,
            child: Container(
              width: 86,
              height: 66,
              decoration: BoxDecoration(
                gradient: PiazlyColors.violetGradient,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: <BoxShadow>[
                  BoxShadow(color: PiazlyColors.violet.withValues(alpha: 0.3), blurRadius: 14, offset: const Offset(0, 6)),
                ],
              ),
              child: Icon(front, color: Colors.white, size: 36),
            ),
          ),
        ),
        const Positioned(
          right: 26,
          top: 4,
          child: Icon(Icons.auto_awesome_rounded, color: AppColors.brandOrange, size: 22),
        ),
      ],
    ),
  );
}
