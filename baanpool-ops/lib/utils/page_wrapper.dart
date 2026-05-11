import 'package:flutter/material.dart';

/// Responsive page content wrapper.
///
/// On desktop (>= [breakpoint]): centers [child] horizontally with a
/// max-width of [maxWidth] and applies [desktopPadding].
/// On mobile: renders [child] at full width with [mobilePadding].
class PageWrapper extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final double breakpoint;
  final EdgeInsetsGeometry mobilePadding;
  final EdgeInsetsGeometry desktopPadding;

  const PageWrapper({
    super.key,
    required this.child,
    this.maxWidth = 1100,
    this.breakpoint = 720,
    this.mobilePadding = const EdgeInsets.all(16),
    this.desktopPadding = const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= breakpoint;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isDesktop ? maxWidth : double.infinity),
        child: Padding(
          padding: isDesktop ? desktopPadding : mobilePadding,
          child: child,
        ),
      ),
    );
  }
}
