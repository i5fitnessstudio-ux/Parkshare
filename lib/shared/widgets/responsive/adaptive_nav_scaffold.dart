import 'package:flutter/material.dart';

import 'responsive_layout.dart';

/// One application section that can render in either navigation mode.
class AdaptiveDestination {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const AdaptiveDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  NavigationDestination get asNavigationBarDestination => NavigationDestination(
    icon: Icon(icon),
    selectedIcon: Icon(selectedIcon),
    label: label,
  );

  NavigationRailDestination get asRailDestination => NavigationRailDestination(
    icon: Icon(icon),
    selectedIcon: Icon(selectedIcon),
    label: Text(label),
  );
}

/// Phase 3 — adaptive navigation shell shared by the two authenticated homes:
///
///   * compact (< 600 dp): the existing phone pattern — `AppBar` +
///     `NavigationBar` at the bottom (unchanged).
///   * medium/expanded (600–1199 dp): a labelled `NavigationRail` on the left
///     (tablet-appropriate, clear labels, maps get the full remaining width).
///   * large (>= 1200 dp): an extended rail (icon + label side by side) with
///     the content centred at [ResponsiveLayout.contentMaxWidth]-ish widths via
///     the caller-provided layout.
///
/// The selected index, the app bar and the body state live with the caller, so
/// navigation, role and page state are preserved exactly as before.
class AdaptiveNavScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  final List<AdaptiveDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget? floatingActionButton;

  const AdaptiveNavScaffold({
    super.key,
    this.appBar,
    required this.body,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.floatingActionButton,
  });

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;

    return Scaffold(
      appBar: appBar,
      body: compact
          ? body
          : Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SafeArea(
                  child: NavigationRail(
                    selectedIndex: selectedIndex,
                    onDestinationSelected: onDestinationSelected,
                    // An extended rail draws the label text itself, so the
                    // labelType must be `none` while extended (the framework
                    // asserts on extended + `all`).
                    labelType: context.isDesktop
                        ? NavigationRailLabelType.none
                        : NavigationRailLabelType.all,
                    extended: context.isDesktop,
                    minExtendedWidth: 200,
                    groupAlignment: -0.9,
                    leading: null,
                    destinations: [
                      for (final d in destinations) d.asRailDestination,
                    ],
                  ),
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(child: body),
              ],
            ),
      bottomNavigationBar: compact
          ? NavigationBar(
              selectedIndex: selectedIndex,
              onDestinationSelected: onDestinationSelected,
              destinations: [
                for (final d in destinations) d.asNavigationBarDestination,
              ],
            )
          : null,
      floatingActionButton: floatingActionButton,
    );
  }
}
