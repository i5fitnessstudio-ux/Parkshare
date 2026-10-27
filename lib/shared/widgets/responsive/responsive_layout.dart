import 'package:flutter/material.dart';

/// Material 3 window-size classes simplified to the four tiers ParkShare uses.
enum LayoutBreakpoint {
  /// < 600 dp — phones, split-screen halves, small foldable front screens.
  compact,

  /// 600–839 dp — unfolded foldables, small tablets (7" portrait).
  medium,

  /// 840–1199 dp — 7"/10" tablets (portrait and landscape), desktop windows.
  expanded,

  /// >= 1200 dp — large tablets, desktop, web.
  large,
}

/// Central responsive layout system.
///
/// Single source of truth for the breakpoints used across ParkShare. Screens
/// and widgets query [of] (or the [ResponsiveContext] extension) and adapt
/// with Flutter's own layout primitives — MediaQuery/LayoutBuilder/Expanded/
/// Wrap etc. — instead of guessing from device names or physical sizes.
///
/// Breakpoints (logical pixels, aligned with Material 3 window-size classes):
///   | width        | tier     | guidance                          |
///   |--------------|----------|-----------------------------------|
///   | < 600        | compact  | single-column phone layouts       |
///   | 600–839      | medium   | 2-column tablet / foldable        |
///   | 840–1199     | expanded | wider tablet / desktop windows    |
///   | >= 1200      | large    | desktop side nav + capped content |
class ResponsiveLayout {
  ResponsiveLayout._();

  static const double compactMaxWidth = 599.0;
  static const double mediumMaxWidth = 839.0;
  static const double expandedMaxWidth = 1199.0;

  /// Content cap for single-column forms (login, register, OTP, vehicle form,
  /// profile). Keeps fields from stretching edge-to-edge on desktop.
  static const double formMaxWidth = 520.0;

  /// Content cap for card/list/detail screens (bookings, parkings, dashboard,
  /// chat). Detail screens that want a tighter column pass a smaller value.
  static const double contentMaxWidth = 1000.0;

  /// Reading width for long-form text (legal documents).
  static const double readingMaxWidth = 720.0;

  /// Map overlay width cap (search bar + suggestions + preview card).
  static const double mapOverlayMaxWidth = 520.0;

  static LayoutBreakpoint fromWidth(double width) {
    if (width <= compactMaxWidth) return LayoutBreakpoint.compact;
    if (width <= mediumMaxWidth) return LayoutBreakpoint.medium;
    if (width <= expandedMaxWidth) return LayoutBreakpoint.expanded;
    return LayoutBreakpoint.large;
  }

  static LayoutBreakpoint of(BuildContext context) =>
      fromWidth(MediaQuery.sizeOf(context).width);

  static bool isCompact(BuildContext context) =>
      of(context) == LayoutBreakpoint.compact;

  /// True on any layout wide enough to stop pretending to be a phone.
  static bool isTabletOrWider(BuildContext context) =>
      of(context) != LayoutBreakpoint.compact;

  static bool isDesktop(BuildContext context) =>
      of(context) == LayoutBreakpoint.large;
}

/// Convenience accessors so screens read `context.isTabletOrWider` instead of
/// repeating `ResponsiveLayout.of(context)`.
extension ResponsiveContext on BuildContext {
  LayoutBreakpoint get breakpoint => ResponsiveLayout.of(this);

  bool get isCompact => breakpoint == LayoutBreakpoint.compact;

  bool get isTabletOrWider => breakpoint != LayoutBreakpoint.compact;

  bool get isDesktop => breakpoint == LayoutBreakpoint.large;

  double get screenWidth => MediaQuery.sizeOf(this).width;

  double get screenHeight => MediaQuery.sizeOf(this).height;
}

/// Constrains a child's cross-axis width to [maxWidth] and centres it when the
/// parent has more room (tablet/desktop), while behaving exactly like a plain
/// child on narrow phones (parent width <= [maxWidth]).
///
/// This is the "readable content width" tool: it keeps forms, lists and detail
/// screens from stretching edge-to-edge on wide windows without changing any
/// phone layout.
class ConstrainedContent extends StatelessWidget {
  final Widget child;

  /// Horizontal cap. Use one of [ResponsiveLayout]'s width constants, or a
  /// custom value for screens with their own target width.
  final double maxWidth;

  /// Extra cross-axis padding applied to the child (always, so padding is
  /// consistent on every size).
  final EdgeInsetsGeometry? padding;

  /// Whether to centre the content when the parent is wider than [maxWidth]
  /// (default) or leave it anchored to the start.
  final bool center;

  const ConstrainedContent({
    super.key,
    required this.child,
    this.maxWidth = ResponsiveLayout.contentMaxWidth,
    this.padding,
    this.center = true,
  });

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding ?? EdgeInsets.zero, child: child);
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        if (available <= maxWidth) return content;
        return Align(
          alignment: center ? Alignment.topCenter : Alignment.topLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: content,
          ),
        );
      },
    );
  }
}

/// Adaptive grid that picks the column count from the available width instead
/// of a fixed `crossAxisCount`. Use wherever the current `GridView.count(2)`
/// would leave oversized cells on tablets (photo picker, amenities).
class ResponsiveGrid extends StatelessWidget {
  final List<Widget> children;

  /// Maximum tile width; the grid derives 2..N columns from it.
  final double maxCrossAxisExtent;

  final double mainAxisSpacing;
  final double crossAxisSpacing;

  /// Optional fixed tile height. Leave null to let tiles size from
  /// [childAspectRatio].
  final double? mainAxisExtent;
  final double childAspectRatio;

  /// True when the grid sits inside a scrollable (shrink-wraps + disables its
  /// own scrolling). False for a standalone scrollable grid.
  final bool shrinkWrap;

  final EdgeInsetsGeometry padding;

  const ResponsiveGrid({
    super.key,
    required this.children,
    this.maxCrossAxisExtent = 200,
    this.mainAxisSpacing = 12,
    this.crossAxisSpacing = 12,
    this.mainAxisExtent,
    this.childAspectRatio = 1,
    this.shrinkWrap = false,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return GridView(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      padding: padding,
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: maxCrossAxisExtent,
        mainAxisSpacing: mainAxisSpacing,
        crossAxisSpacing: crossAxisSpacing,
        mainAxisExtent: mainAxisExtent,
        childAspectRatio: childAspectRatio,
      ),
      children: children,
    );
  }
}

/// Responsive row of stat/value tiles: fills rows with equal-width tiles that
/// flow onto more columns on wider layouts (no fixed grid count), and grows
/// vertically with text scale.
class ResponsiveTileRow extends StatelessWidget {
  final List<Widget> children;

  /// Minimum tile width so tiles never collapse to slivers on wide layouts.
  final double minTileWidth;

  final double spacing;

  const ResponsiveTileRow({
    super.key,
    required this.children,
    this.minTileWidth = 140,
    this.spacing = 10,
  });

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / (minTileWidth + spacing))
            .floor()
            .clamp(1, children.length);
        final rows = <List<Widget>>[];
        for (var i = 0; i < children.length; i += columns) {
          rows.add(
            children.sublist(
              i,
              i + columns > children.length ? children.length : i + columns,
            ),
          );
        }
        return Column(
          children: [
            for (var r = 0; r < rows.length; r++) ...[
              if (r > 0) SizedBox(height: spacing),
              Row(
                children: [
                  for (var c = 0; c < columns; c++) ...[
                    if (c > 0) SizedBox(width: spacing),
                    // Empty trailing slots keep every tile the same width.
                    Expanded(
                      child: c < rows[r].length ? rows[r][c] : SizedBox(),
                    ),
                  ],
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}
