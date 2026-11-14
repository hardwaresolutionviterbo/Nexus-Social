import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// Monogramma del brand: «V» bianca su gradiente blu → arancio, con bagliore.
class NexusMark extends StatelessWidget {
  const NexusMark({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'VoxLine',
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: AppColors.brandGradient,
          borderRadius: BorderRadius.circular(size * 0.32),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.22),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.brandOrange.withValues(alpha: 0.35),
              blurRadius: size * 0.6,
              offset: Offset(size * 0.1, size * 0.16),
            ),
            BoxShadow(
              color: AppColors.brandBlue.withValues(alpha: 0.30),
              blurRadius: size * 0.6,
              offset: Offset(-size * 0.1, size * 0.06),
            ),
          ],
        ),
        child: ExcludeSemantics(
          child: Text(
            'V',
            style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.56,
              fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

/// Scritta «VoxLine» con «Line» in arancio.
class NexusWordmark extends StatelessWidget {
  const NexusWordmark({super.key, this.fontSize = 17});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextStyle style = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w900,
      fontStyle: FontStyle.italic,
      letterSpacing: -0.4,
      height: 1.1,
      color: scheme.onSurface,
    );
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: 'Vox', style: style),
          TextSpan(
            text: 'Line',
            style: style.copyWith(color: scheme.primary),
          ),
        ],
      ),
      semanticsLabel: 'VoxLine',
    );
  }
}

/// Contenitore arrotondato «in vetro» usato per le sezioni delle schermate.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.06),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Card(
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Etichetta «Fase N» che indica quando arriverà una funzione.
class PhaseChip extends StatelessWidget {
  const PhaseChip({super.key, required this.phase, this.onAccent = false});

  final int phase;

  /// Versione bianca, da usare sopra un fondo colorato.
  final bool onAccent;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color color = onAccent ? Colors.white : scheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: onAccent ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        'Fase $phase',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

/// Comparsa morbida (dissolvenza e leggero scorrimento verso l'alto).
class FadeSlideIn extends StatelessWidget {
  const FadeSlideIn({super.key, required this.child, this.delay = 0});

  final Widget child;

  /// Ritardo relativo, da 0 a 1, per far entrare gli elementi uno dopo l'altro.
  final double delay;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 420 + (delay * 360).round()),
      curve: Interval(delay.clamp(0.0, 0.6).toDouble(), 1, curve: Curves.easeOutCubic),
      child: child,
      builder: (BuildContext context, double t, Widget? child) {
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 18),
            child: child,
          ),
        );
      },
    );
  }
}

/// Anteprima di una funzione futura: copertina colorata, descrizione ed elenco
/// di cosa arriverà.
class PhasePreview extends StatelessWidget {
  const PhasePreview({
    super.key,
    required this.icon,
    required this.phase,
    required this.title,
    required this.description,
    this.features = const <String>[],
    this.footer,
    this.accent,
  });

  final IconData icon;
  final int phase;
  final String title;
  final String description;
  final List<String> features;
  final Widget? footer;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Color color = accent ?? scheme.primary;

    return ListView(
      padding: AppSpacing.pagePadding,
      children: [
        FadeSlideIn(
          child: _HeroCard(
            icon: icon,
            phase: phase,
            title: title,
            description: description,
            color: color,
          ),
        ),
        if (features.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          FadeSlideIn(
            delay: 0.15,
            child: SectionCard(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cosa arriverà',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  for (int i = 0; i < features.length; i++) ...[
                    if (i > 0) const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: AppColors.accentGradient(color),
                            boxShadow: [
                              BoxShadow(
                                color: color.withValues(alpha: 0.30),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              features[i],
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
        if (footer != null) ...[
          const SizedBox(height: AppSpacing.md),
          FadeSlideIn(delay: 0.3, child: footer!),
        ],
        const SizedBox(height: AppSpacing.lg),
        Center(
          child: Text(
            'Disponibile nella Fase $phase',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// Copertina della sezione: gradiente acceso, cerchi luminosi e icona in vetro.
class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.icon,
    required this.phase,
    required this.title,
    required this.description,
    required this.color,
  });

  final IconData icon;
  final int phase;
  final String title;
  final String description;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: AppColors.accentGradient(color),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.38),
            blurRadius: 32,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -40,
            top: -50,
            child: _Glow(size: 170, alpha: 0.20),
          ),
          Positioned(
            left: -30,
            bottom: -60,
            child: _Glow(size: 140, alpha: 0.12),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Icon(icon, color: Colors.white, size: 28),
                    ),
                    const Spacer(),
                    PhaseChip(phase: phase, onAccent: true),
                  ],
                ),
                const SizedBox(height: 22),
                Text(
                  title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.88),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.alpha});

  final double size;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              Colors.white.withValues(alpha: alpha),
              Colors.white.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}

/// Campanella in un cerchio di vetro, con contatore e foglio delle notifiche.
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key, this.count = 0, this.onPressed});

  final int count;
  final VoidCallback? onPressed;

  static Future<void> showNotifications(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => const _NotificationsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    return IconButton(
      tooltip: 'Notifiche',
      onPressed: onPressed ?? () => showNotifications(context),
      style: IconButton.styleFrom(
        backgroundColor: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.white.withValues(alpha: 0.9),
        side: BorderSide(
          color: isDark
              ? Colors.white.withValues(alpha: 0.10)
              : theme.colorScheme.outline,
        ),
        fixedSize: const Size(44, 44),
      ),
      icon: Badge.count(
        count: count,
        isLabelVisible: count > 0,
        backgroundColor: AppColors.brandOrange,
        child: Icon(
          Icons.notifications_none_rounded,
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}

class _NotificationsSheet extends StatelessWidget {
  const _NotificationsSheet();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text('Notifiche', style: theme.textTheme.titleLarge),
              const Spacer(),
              const PhaseChip(phase: 4),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.orangeGradient,
              boxShadow: [
                BoxShadow(
                  color: AppColors.brandOrange.withValues(alpha: 0.35),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.notifications_none_rounded,
              color: Colors.white,
              size: 34,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Nessuna notifica per ora', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            'Qui arriveranno messaggi, richieste di contatto e avvisi importanti.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Fondo con bagliori: blu elettrico in alto a sinistra, arancio in basso a destra.
class NexusBackdrop extends StatelessWidget {
  const NexusBackdrop({super.key, required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final double strength = isDark ? 1 : 0.55;
    return IgnorePointer(
      child: Stack(
        children: [
          const SizedBox.expand(),
          Positioned(
            left: -140,
            top: -120,
            child: _GlowBlob(
              color: AppColors.brandBlue,
              size: 420,
              alpha: 0.22 * strength,
            ),
          ),
          Positioned(
            right: -160,
            bottom: 40,
            child: _GlowBlob(
              color: AppColors.brandOrange,
              size: 440,
              alpha: 0.16 * strength,
            ),
          ),
          Positioned(
            right: -80,
            top: 160,
            child: _GlowBlob(
              color: AppColors.brandViolet,
              size: 260,
              alpha: 0.10 * strength,
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({
    required this.color,
    required this.size,
    required this.alpha,
  });

  final Color color;
  final double size;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: alpha), color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}
