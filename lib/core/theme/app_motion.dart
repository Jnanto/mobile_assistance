import 'package:flutter/material.dart';

/// Duraciones y curvas de las animaciones de la app.
abstract final class AppMotion {
  static const Duration short = Duration(milliseconds: 200);
  static const Duration medium = Duration(milliseconds: 320);
  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
}

/// Transición entre pantallas: la nueva entra deslizándose un poco desde la
/// derecha mientras aparece; la anterior se corre a la izquierda y se
/// atenúa (estilo "eje compartido" de Material).
class SelvaPageTransitionsBuilder extends PageTransitionsBuilder {
  const SelvaPageTransitionsBuilder();

  @override
  Duration get transitionDuration => AppMotion.medium;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final incoming = CurvedAnimation(
      parent: animation,
      curve: AppMotion.enter,
      reverseCurve: AppMotion.exit,
    );
    final outgoing = CurvedAnimation(
      parent: secondaryAnimation,
      curve: AppMotion.enter,
      reverseCurve: AppMotion.exit,
    );
    return FadeTransition(
      opacity: incoming,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0.08, 0),
          end: Offset.zero,
        ).animate(incoming),
        child: FadeTransition(
          opacity: Tween(begin: 1.0, end: 0.6).animate(outgoing),
          child: SlideTransition(
            position: Tween(
              begin: Offset.zero,
              end: const Offset(-0.05, 0),
            ).animate(outgoing),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Aparición suave (fundido y leve subida) de un elemento al construirse.
/// [index] escalona varios elementos de una lista.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({super.key, required this.child, this.index = 0});

  final Widget child;
  final int index;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  static const _step = Duration(milliseconds: 45);
  static const _maxSteps = 6;

  late final AnimationController _controller;
  late final Animation<double> _progress;

  @override
  void initState() {
    super.initState();
    final steps = widget.index.clamp(0, _maxSteps);
    final delay = _step * steps;
    final total = delay + AppMotion.medium;
    _controller = AnimationController(vsync: this, duration: total)..forward();
    _progress = CurvedAnimation(
      parent: _controller,
      curve: Interval(
        delay.inMilliseconds / total.inMilliseconds,
        1,
        curve: AppMotion.enter,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _progress,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(_progress),
        child: widget.child,
      ),
    );
  }
}

/// Como [IndexedStack] (conserva el estado de cada pestaña), pero la pestaña
/// que se muestra aparece con un fundido corto.
class FadeIndexedStack extends StatefulWidget {
  const FadeIndexedStack({
    super.key,
    required this.index,
    required this.children,
  });

  final int index;
  final List<Widget> children;

  @override
  State<FadeIndexedStack> createState() => _FadeIndexedStackState();
}

class _FadeIndexedStackState extends State<FadeIndexedStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.short,
    value: 1,
  );

  @override
  void didUpdateWidget(FadeIndexedStack old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _controller, curve: AppMotion.enter);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.015),
          end: Offset.zero,
        ).animate(curved),
        child: IndexedStack(index: widget.index, children: widget.children),
      ),
    );
  }
}

/// Envuelve los primeros elementos de una lista en [FadeSlideIn], con un
/// escalonado corto. Los espacios ([SizedBox]) no cuentan y los elementos
/// después del octavo se muestran sin animación.
List<Widget> staggered(List<Widget> children) {
  var index = 0;
  return [
    for (final child in children)
      if (child is SizedBox || index >= 8)
        child
      else
        FadeSlideIn(index: index++, child: child),
  ];
}
