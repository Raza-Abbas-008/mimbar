import 'package:flutter/foundation.dart';

/// Gmail-style multi-select of events, shared by the Home, Create and
/// Calendar tabs. Long-press starts it; while anything is selected a tap
/// toggles instead of opening.
class EventSelection extends ChangeNotifier {
  final ids = <int>{};

  /// Event ids each tab is currently showing, for Select all.
  final _visible = <String, List<int>>{};

  bool get active => ids.isNotEmpty;

  bool has(int id) => ids.contains(id);

  void toggle(int id) {
    if (!ids.remove(id)) ids.add(id);
    notifyListeners();
  }

  /// Called by a tab while building; doesn't notify.
  void setVisible(String tab, Iterable<int> list) => _visible[tab] = list.toList();

  void selectAll(String tab) {
    ids.addAll(_visible[tab] ?? const []);
    notifyListeners();
  }

  void clear() {
    if (ids.isEmpty) return;
    ids.clear();
    notifyListeners();
  }
}

final eventSelection = EventSelection();
