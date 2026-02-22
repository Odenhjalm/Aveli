import 'dart:collection';

class HomeAudioQueueItem {
  const HomeAudioQueueItem({required this.id, required this.isPlayable});

  final String id;
  final bool isPlayable;
}

class HomeAudioPlaylistQueue {
  List<HomeAudioQueueItem> _items = const <HomeAudioQueueItem>[];
  int _currentIndex = 0;
  final Set<String> _failedIds = <String>{};

  List<HomeAudioQueueItem> get items => _items;
  int? get currentIndex => _items.isEmpty ? null : _currentIndex;
  HomeAudioQueueItem? get currentItem =>
      _items.isEmpty ? null : _items[_currentIndex];
  Set<String> get failedIds => UnmodifiableSetView(_failedIds);

  bool get hasPlayableItems => _items.any((item) => item.isPlayable);

  bool get hasRemainingPlayableItems =>
      _items.any((item) => item.isPlayable && !_failedIds.contains(item.id));

  bool get allPlayableItemsFailed =>
      hasPlayableItems && !hasRemainingPlayableItems;

  int indexOf(String id) {
    final normalized = id.trim();
    if (normalized.isEmpty) return -1;
    return _items.indexWhere((item) => item.id == normalized);
  }

  void setItems(List<HomeAudioQueueItem> items, {String? preferredCurrentId}) {
    final normalized = <HomeAudioQueueItem>[
      for (final item in items)
        if (item.id.trim().isNotEmpty)
          HomeAudioQueueItem(id: item.id.trim(), isPlayable: item.isPlayable),
    ];
    final currentId = (preferredCurrentId ?? currentItem?.id)?.trim();
    _items = List<HomeAudioQueueItem>.unmodifiable(normalized);

    if (_items.isEmpty) {
      _currentIndex = 0;
      _failedIds.clear();
      return;
    }

    _failedIds.removeWhere((id) => indexOf(id) < 0);
    final retainedIndex = currentId == null || currentId.isEmpty
        ? -1
        : indexOf(currentId);
    if (retainedIndex >= 0) {
      _currentIndex = retainedIndex;
      return;
    }
    if (_currentIndex >= _items.length) {
      _currentIndex = _items.length - 1;
    }
  }

  HomeAudioQueueItem? playAt(int index) {
    if (_items.isEmpty) return null;
    _currentIndex = _normalizeIndex(index);
    return _items[_currentIndex];
  }

  HomeAudioQueueItem? playNext({bool auto = true}) {
    if (_items.isEmpty) return null;
    if (!auto && _items.length == 1) {
      final only = _items.first;
      if (!only.isPlayable || _failedIds.contains(only.id)) return null;
      _currentIndex = 0;
      return only;
    }
    final includeCurrent = _items.length == 1;
    return _advance(step: 1, includeCurrent: includeCurrent);
  }

  HomeAudioQueueItem? playPrev() {
    if (_items.isEmpty) return null;
    final includeCurrent = _items.length == 1;
    return _advance(step: -1, includeCurrent: includeCurrent);
  }

  void markCurrentFailed() {
    final current = currentItem;
    if (current == null) return;
    _failedIds.add(current.id);
  }

  void markFailed(String id) {
    final normalized = id.trim();
    if (normalized.isEmpty) return;
    if (indexOf(normalized) < 0) return;
    _failedIds.add(normalized);
  }

  void clearFailure(String id) {
    _failedIds.remove(id.trim());
  }

  void clearFailures() {
    _failedIds.clear();
  }

  HomeAudioQueueItem? _advance({
    required int step,
    required bool includeCurrent,
  }) {
    if (_items.isEmpty) return null;
    final total = _items.length;
    final start = _currentIndex;
    for (var offset = 0; offset < total; offset++) {
      final normalizedOffset = includeCurrent ? offset : offset + 1;
      final candidateIndex = _normalizeIndex(start + (normalizedOffset * step));
      final candidate = _items[candidateIndex];
      if (!candidate.isPlayable) continue;
      if (_failedIds.contains(candidate.id)) continue;
      _currentIndex = candidateIndex;
      return candidate;
    }
    return null;
  }

  int _normalizeIndex(int raw) {
    final total = _items.length;
    if (total == 0) return 0;
    final mod = raw % total;
    return mod < 0 ? mod + total : mod;
  }
}
