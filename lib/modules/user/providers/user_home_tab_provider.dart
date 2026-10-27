import 'package:flutter/foundation.dart';

/// Which bottom-nav tab of [UserHomeScreen] is showing.
///
/// Tabs are named, not indexed, so a caller can say "show the map" without
/// knowing the order. The vehicle screen uses this for its "Save & Find
/// Parking" button: after a successful save it switches the EXISTING Map tab
/// instead of pushing a second, duplicate map screen.
enum UserTab { vehicles, map, bookings, inbox }

/// The user home screen listens to this; anything else (the vehicle form after
/// a save) simply calls [show] to request a tab. A single source of truth means
/// the bottom-nav bar and the body can never disagree about the current tab.
class UserHomeTabProvider extends ChangeNotifier {
  UserTab _tab = UserTab.vehicles;

  UserTab get tab => _tab;

  int get index => _tab.index;

  /// Switches the tab. Same-value calls are ignored so a save-then-navigate
  /// never rebuilds the tree twice.
  void show(UserTab tab) {
    if (_tab == tab) return;
    _tab = tab;
    notifyListeners();
  }

  void showIndex(int i) {
    if (i < 0 || i >= UserTab.values.length) return;
    show(UserTab.values[i]);
  }
}
