import 'package:flutter/material.dart';

/// Responds on touch-down, not on release: the child presses in instantly and
/// springs back on lift. Moving more than [slop] cancels the press so scrolling
/// a list of cards never leaves one stuck down. Purely visual: taps are still
/// handled by the child's own InkWell / GestureDetector.
class Pressable extends StatefulWidget {
  final Widget child;
  final double scale;
  final double slop;

  const Pressable({
    super.key,
    required this.child,
    this.scale = 0.97,
    this.slop = 10,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  Offset? _origin;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    return Listener(
      onPointerDown: (e) {
        _origin = e.position;
        _set(true);
      },
      onPointerMove: (e) {
        if (_origin != null && (e.position - _origin!).distance > widget.slop) {
          _set(false);
        }
      },
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: reduce
          ? AnimatedOpacity(
              opacity: _down ? 0.7 : 1,
              duration: const Duration(milliseconds: 120),
              child: widget.child,
            )
          : AnimatedScale(
              scale: _down ? widget.scale : 1,
              // Fast in, gentle critically-damped settle out.
              duration: Duration(milliseconds: _down ? 90 : 260),
              curve: _down ? Curves.easeOut : Curves.easeOutCubic,
              child: widget.child,
            ),
    );
  }
}
