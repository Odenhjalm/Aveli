import 'package:flutter/foundation.dart';

class Gate extends ChangeNotifier {
  bool _allowed = false;
  bool get allowed => _allowed;

  void allow() {
    if (!_allowed) {
      _allowed = true;
      notifyListeners();
    }
  }

  void reset() {
    if (_allowed) {
      _allowed = false;
      notifyListeners();
    }
  }
}

final Gate gate = Gate();
