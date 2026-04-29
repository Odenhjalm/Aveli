import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aveli/data/models/home_player_library.dart';
import 'package:aveli/features/home/application/home_audio_controller.dart';
import 'package:aveli/features/home/application/home_audio_session_controller.dart';
import 'package:aveli/features/home/data/home_audio_repository.dart';
import 'package:aveli/shared/utils/resolved_media_contract.dart';

import '../helpers/fake_home_audio_engine.dart';

const _testHomeplayerLogo = HomePlayerLogoSet(
  closed: HomePlayerLogoAsset(
    assetKey: 'homeplayer_logo_closed',
    resolvedUrl:
        'https://storage.test/storage/v1/object/public/public-media/home-player/logos/v1/homeplayer_logo_closed.png',
  ),
  open: HomePlayerLogoAsset(
    assetKey: 'homeplayer_logo_open',
    resolvedUrl:
        'https://storage.test/storage/v1/object/public/public-media/home-player/logos/v1/homeplayer_logo_open.png',
  ),
);

void main() {
  test('HomeAudioState preserves backend payload order exactly', () {
    final first = _item(
      title: 'Second in time but first in payload',
      mediaId: 'media-2',
      url: 'https://cdn.test/audio/second.mp3',
      createdAt: DateTime.utc(2026, 4, 22, 10, 0),
    );
    final second = _item(
      title: 'First in time but second in payload',
      mediaId: 'media-1',
      url: 'https://cdn.test/audio/first.mp3',
      createdAt: DateTime.utc(2026, 4, 22, 12, 0),
    );

    final state = HomeAudioState.fromPayload(
      HomeAudioFeedPayload(
        items: [first, second],
        homeplayerLogo: _testHomeplayerLogo,
        textBundle: const HomePlayerTextBundle(),
      ),
    );

    expect(state.items, orderedEquals([first, second]));
  });

  test(
    'session controller freezes queue order and selects duplicates by index',
    () async {
      final engineFactory = FakeHomeAudioEngineFactory();
      final container = ProviderContainer(
        overrides: [
          homeAudioEngineFactoryProvider.overrideWithValue(
            engineFactory.create,
          ),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(
        homeAudioSessionControllerProvider,
        (previous, next) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);

      final controller = container.read(
        homeAudioSessionControllerProvider.notifier,
      );
      await controller.hydrateQueue([
        _item(
          title: 'Entry A',
          mediaId: 'duplicate-media',
          url: 'https://cdn.test/audio/a.mp3',
          createdAt: DateTime.utc(2026, 4, 22, 11, 0),
        ),
        _item(
          title: 'Entry B',
          mediaId: 'duplicate-media',
          url: 'https://cdn.test/audio/b.mp3',
          createdAt: DateTime.utc(2026, 4, 22, 10, 0),
        ),
        _processingItem(
          title: 'Ignored processing row',
          mediaId: 'media-processing',
          createdAt: DateTime.utc(2026, 4, 22, 9, 0),
        ),
      ]);

      var state = container.read(homeAudioSessionControllerProvider);
      expect(state.queue.map((entry) => entry.index), orderedEquals([0, 1]));
      expect(
        state.queue.map((entry) => entry.resolvedUrl),
        orderedEquals([
          'https://cdn.test/audio/a.mp3',
          'https://cdn.test/audio/b.mp3',
        ]),
      );
      expect(state.currentIndex, 0);
      expect(engineFactory.createCount, 1);
      expect(
        engineFactory.single.loadedUrls,
        orderedEquals(['https://cdn.test/audio/a.mp3']),
      );

      await controller.selectIndex(1);

      state = container.read(homeAudioSessionControllerProvider);
      expect(state.currentIndex, 1);
      expect(state.currentEntry?.title, 'Entry B');
      expect(engineFactory.createCount, 1);
      expect(
        engineFactory.single.loadedUrls.last,
        'https://cdn.test/audio/b.mp3',
      );
    },
  );

  test(
    'session controller preserves volume and engine instance across track switches',
    () async {
      final engineFactory = FakeHomeAudioEngineFactory();
      final container = ProviderContainer(
        overrides: [
          homeAudioEngineFactoryProvider.overrideWithValue(
            engineFactory.create,
          ),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(
        homeAudioSessionControllerProvider,
        (previous, next) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);

      final controller = container.read(
        homeAudioSessionControllerProvider.notifier,
      );
      await controller.hydrateQueue([
        _item(
          title: 'Track One',
          mediaId: 'media-1',
          url: 'https://cdn.test/audio/one.mp3',
          createdAt: DateTime.utc(2026, 4, 22, 11, 0),
        ),
        _item(
          title: 'Track Two',
          mediaId: 'media-2',
          url: 'https://cdn.test/audio/two.mp3',
          createdAt: DateTime.utc(2026, 4, 22, 10, 0),
        ),
      ]);

      await controller.setVolume(0.32);
      await controller.play();
      await controller.selectIndex(1);

      final state = container.read(homeAudioSessionControllerProvider);
      expect(state.volume, closeTo(0.32, 0.0001));
      expect(state.lastNonZeroVolume, closeTo(0.32, 0.0001));
      expect(state.playbackWanted, isTrue);
      expect(engineFactory.createCount, 1);
      expect(engineFactory.single.playCalls, greaterThanOrEqualTo(2));
      expect(engineFactory.single.volumeHistory.last, closeTo(0.32, 0.0001));
    },
  );

  test(
    'refresh during active playback stages candidate without replacing active queue',
    () async {
      final engineFactory = FakeHomeAudioEngineFactory();
      final container = ProviderContainer(
        overrides: [
          homeAudioEngineFactoryProvider.overrideWithValue(
            engineFactory.create,
          ),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(
        homeAudioSessionControllerProvider,
        (previous, next) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);

      final controller = container.read(
        homeAudioSessionControllerProvider.notifier,
      );
      await controller.hydrateQueue([
        _item(
          title: 'Track One',
          mediaId: 'media-1',
          url: 'https://cdn.test/audio/one.mp3',
          createdAt: DateTime.utc(2026, 4, 22, 11, 0),
        ),
        _item(
          title: 'Track Two',
          mediaId: 'media-2',
          url: 'https://cdn.test/audio/two.mp3',
          createdAt: DateTime.utc(2026, 4, 22, 10, 0),
        ),
      ]);

      await controller.play();
      await controller.hydrateQueue([
        _item(
          title: 'Fresh Lead',
          mediaId: 'media-9',
          url: 'https://cdn.test/audio/fresh.mp3',
          createdAt: DateTime.utc(2026, 4, 22, 12, 0),
        ),
        _item(
          title: 'Track One Updated',
          mediaId: 'media-1',
          url: 'https://cdn.test/audio/one-updated.mp3',
          createdAt: DateTime.utc(2026, 4, 22, 11, 30),
        ),
      ]);

      final state = container.read(homeAudioSessionControllerProvider);
      expect(
        state.queue.map((entry) => entry.title),
        orderedEquals(['Track One', 'Track Two']),
      );
      expect(state.currentIndex, 0);
      expect(state.isPlaying, isTrue);
      expect(state.hasStagedSnapshot, isTrue);
      expect(state.replacementAllowed, isFalse);
      expect(
        state.stagedQueue.map((entry) => entry.title),
        orderedEquals(['Fresh Lead', 'Track One Updated']),
      );
      expect(engineFactory.createCount, 1);
      expect(
        engineFactory.single.loadedUrls,
        orderedEquals(['https://cdn.test/audio/one.mp3']),
      );
    },
  );

  test(
    'refresh during paused hydrated session stages candidate without replacing active queue',
    () async {
      final engineFactory = FakeHomeAudioEngineFactory();
      final container = ProviderContainer(
        overrides: [
          homeAudioEngineFactoryProvider.overrideWithValue(
            engineFactory.create,
          ),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(
        homeAudioSessionControllerProvider,
        (previous, next) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);

      final controller = container.read(
        homeAudioSessionControllerProvider.notifier,
      );
      await controller.hydrateQueue([
        _item(
          title: 'Track One',
          mediaId: 'media-1',
          url: 'https://cdn.test/audio/one.mp3',
          createdAt: DateTime.utc(2026, 4, 22, 11, 0),
        ),
        _item(
          title: 'Track Two',
          mediaId: 'media-2',
          url: 'https://cdn.test/audio/two.mp3',
          createdAt: DateTime.utc(2026, 4, 22, 10, 0),
        ),
      ]);

      await controller.selectIndex(1);
      await controller.hydrateQueue([
        _item(
          title: 'Paused Refresh Lead',
          mediaId: 'media-7',
          url: 'https://cdn.test/audio/paused-fresh.mp3',
          createdAt: DateTime.utc(2026, 4, 22, 12, 0),
        ),
      ]);

      final state = container.read(homeAudioSessionControllerProvider);
      expect(state.currentIndex, 1);
      expect(state.isPlaying, isFalse);
      expect(state.playbackWanted, isFalse);
      expect(
        state.queue.map((entry) => entry.title),
        orderedEquals(['Track One', 'Track Two']),
      );
      expect(state.hasStagedSnapshot, isTrue);
      expect(
        state.stagedQueue.map((entry) => entry.title),
        orderedEquals(['Paused Refresh Lead']),
      );
      expect(engineFactory.createCount, 1);
      expect(
        engineFactory.single.loadedUrls,
        orderedEquals([
          'https://cdn.test/audio/one.mp3',
          'https://cdn.test/audio/two.mp3',
        ]),
      );
    },
  );

  test(
    'multiple refreshes replace the staged candidate without touching the active queue',
    () async {
      final engineFactory = FakeHomeAudioEngineFactory();
      final container = ProviderContainer(
        overrides: [
          homeAudioEngineFactoryProvider.overrideWithValue(
            engineFactory.create,
          ),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(
        homeAudioSessionControllerProvider,
        (previous, next) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);

      final controller = container.read(
        homeAudioSessionControllerProvider.notifier,
      );
      await controller.hydrateQueue([
        _item(
          title: 'Track One',
          mediaId: 'media-1',
          url: 'https://cdn.test/audio/one.mp3',
          createdAt: DateTime.utc(2026, 4, 22, 11, 0),
        ),
        _item(
          title: 'Track Two',
          mediaId: 'media-2',
          url: 'https://cdn.test/audio/two.mp3',
          createdAt: DateTime.utc(2026, 4, 22, 10, 0),
        ),
      ]);

      await controller.hydrateQueue([
        _item(
          title: 'First Candidate',
          mediaId: 'media-5',
          url: 'https://cdn.test/audio/first-candidate.mp3',
          createdAt: DateTime.utc(2026, 4, 22, 12, 0),
        ),
      ]);
      await controller.hydrateQueue([
        _item(
          title: 'Latest Candidate',
          mediaId: 'media-6',
          url: 'https://cdn.test/audio/latest-candidate.mp3',
          createdAt: DateTime.utc(2026, 4, 22, 12, 30),
        ),
        _item(
          title: 'Latest Tail',
          mediaId: 'media-7',
          url: 'https://cdn.test/audio/latest-tail.mp3',
          createdAt: DateTime.utc(2026, 4, 22, 12, 15),
        ),
      ]);

      final state = container.read(homeAudioSessionControllerProvider);
      expect(
        state.queue.map((entry) => entry.title),
        orderedEquals(['Track One', 'Track Two']),
      );
      expect(state.hasStagedSnapshot, isTrue);
      expect(
        state.stagedQueue.map((entry) => entry.title),
        orderedEquals(['Latest Candidate', 'Latest Tail']),
      );
      expect(engineFactory.single.loadedUrls, hasLength(1));
      expect(engineFactory.createCount, 1);
    },
  );

  test(
    'refresh removing the active entry stages the latest feed without interrupting the session',
    () async {
      final engineFactory = FakeHomeAudioEngineFactory();
      final container = ProviderContainer(
        overrides: [
          homeAudioEngineFactoryProvider.overrideWithValue(
            engineFactory.create,
          ),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(
        homeAudioSessionControllerProvider,
        (previous, next) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);

      final controller = container.read(
        homeAudioSessionControllerProvider.notifier,
      );
      await controller.hydrateQueue([
        _item(
          title: 'Track One',
          mediaId: 'media-1',
          url: 'https://cdn.test/audio/one.mp3',
          createdAt: DateTime.utc(2026, 4, 22, 11, 0),
        ),
        _item(
          title: 'Track Two',
          mediaId: 'media-2',
          url: 'https://cdn.test/audio/two.mp3',
          createdAt: DateTime.utc(2026, 4, 22, 10, 0),
        ),
      ]);

      await controller.play();
      await controller.selectIndex(1);
      await controller.hydrateQueue(const <HomeAudioFeedItem>[]);

      final state = container.read(homeAudioSessionControllerProvider);
      expect(state.currentIndex, 1);
      expect(state.isPlaying, isTrue);
      expect(
        state.queue.map((entry) => entry.title),
        orderedEquals(['Track One', 'Track Two']),
      );
      expect(state.hasStagedSnapshot, isTrue);
      expect(state.stagedQueue, isEmpty);
      expect(engineFactory.createCount, 1);
      expect(
        engineFactory.single.loadedUrls,
        orderedEquals([
          'https://cdn.test/audio/one.mp3',
          'https://cdn.test/audio/two.mp3',
        ]),
      );
    },
  );

  test(
    'explicit reset adopts the staged snapshot and keeps the engine instance',
    () async {
      final engineFactory = FakeHomeAudioEngineFactory();
      final container = ProviderContainer(
        overrides: [
          homeAudioEngineFactoryProvider.overrideWithValue(
            engineFactory.create,
          ),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(
        homeAudioSessionControllerProvider,
        (previous, next) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);

      final controller = container.read(
        homeAudioSessionControllerProvider.notifier,
      );
      await controller.hydrateQueue([
        _item(
          title: 'Track One',
          mediaId: 'media-1',
          url: 'https://cdn.test/audio/one.mp3',
          createdAt: DateTime.utc(2026, 4, 22, 11, 0),
        ),
        _item(
          title: 'Track Two',
          mediaId: 'media-2',
          url: 'https://cdn.test/audio/two.mp3',
          createdAt: DateTime.utc(2026, 4, 22, 10, 0),
        ),
      ]);

      await controller.setVolume(0.28);
      await controller.hydrateQueue([
        _item(
          title: 'Refresh First',
          mediaId: 'media-4',
          url: 'https://cdn.test/audio/refresh-first.mp3',
          createdAt: DateTime.utc(2026, 4, 22, 12, 0),
        ),
        _item(
          title: 'Refresh Second',
          mediaId: 'media-5',
          url: 'https://cdn.test/audio/refresh-second.mp3',
          createdAt: DateTime.utc(2026, 4, 22, 11, 30),
        ),
      ]);

      await controller.resetSession();

      final state = container.read(homeAudioSessionControllerProvider);
      expect(
        state.queue.map((entry) => entry.title),
        orderedEquals(['Refresh First', 'Refresh Second']),
      );
      expect(state.currentIndex, 0);
      expect(state.playbackWanted, isFalse);
      expect(state.hasStagedSnapshot, isFalse);
      expect(state.replacementAllowed, isFalse);
      expect(state.volume, closeTo(0.28, 0.0001));
      expect(engineFactory.createCount, 1);
      expect(
        engineFactory.single.loadedUrls,
        orderedEquals([
          'https://cdn.test/audio/one.mp3',
          'https://cdn.test/audio/refresh-first.mp3',
        ]),
      );
      expect(engineFactory.single.volumeHistory.last, closeTo(0.28, 0.0001));
    },
  );

  test(
    'manual selection while paused loads the new track without auto-playing',
    () async {
      final engineFactory = FakeHomeAudioEngineFactory();
      final container = ProviderContainer(
        overrides: [
          homeAudioEngineFactoryProvider.overrideWithValue(
            engineFactory.create,
          ),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(
        homeAudioSessionControllerProvider,
        (previous, next) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);

      final controller = container.read(
        homeAudioSessionControllerProvider.notifier,
      );
      await controller.hydrateQueue([
        _item(
          title: 'Track One',
          mediaId: 'media-1',
          url: 'https://cdn.test/audio/one.mp3',
          createdAt: DateTime.utc(2026, 4, 22, 11, 0),
        ),
        _item(
          title: 'Track Two',
          mediaId: 'media-2',
          url: 'https://cdn.test/audio/two.mp3',
          createdAt: DateTime.utc(2026, 4, 22, 10, 0),
        ),
      ]);

      await controller.selectIndex(1);

      final state = container.read(homeAudioSessionControllerProvider);
      expect(state.currentIndex, 1);
      expect(state.playbackWanted, isFalse);
      expect(state.isPlaying, isFalse);
      expect(engineFactory.single.playCalls, 0);
      expect(
        engineFactory.single.loadedUrls,
        orderedEquals([
          'https://cdn.test/audio/one.mp3',
          'https://cdn.test/audio/two.mp3',
        ]),
      );
    },
  );

  test(
    'session controller auto-advances exactly once in queue order and reuses the engine',
    () async {
      final engineFactory = FakeHomeAudioEngineFactory();
      final container = ProviderContainer(
        overrides: [
          homeAudioEngineFactoryProvider.overrideWithValue(
            engineFactory.create,
          ),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(
        homeAudioSessionControllerProvider,
        (previous, next) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);

      final controller = container.read(
        homeAudioSessionControllerProvider.notifier,
      );
      await controller.hydrateQueue([
        _item(
          title: 'Track One',
          mediaId: 'media-1',
          url: 'https://cdn.test/audio/one.mp3',
          createdAt: DateTime.utc(2026, 4, 22, 11, 0),
        ),
        _item(
          title: 'Track Two',
          mediaId: 'media-2',
          url: 'https://cdn.test/audio/two.mp3',
          createdAt: DateTime.utc(2026, 4, 22, 10, 0),
        ),
        _item(
          title: 'Track Three',
          mediaId: 'media-3',
          url: 'https://cdn.test/audio/three.mp3',
          createdAt: DateTime.utc(2026, 4, 22, 9, 0),
        ),
      ]);

      await controller.setVolume(0.42);
      await controller.play();
      engineFactory.single.emitProgress(const Duration(seconds: 12));
      engineFactory.single.emitEnded();
      engineFactory.single.emitEnded();
      await Future<void>.delayed(Duration.zero);

      final state = container.read(homeAudioSessionControllerProvider);
      expect(state.currentIndex, 1);
      expect(state.activeEpoch, 2);
      expect(state.handledEndedEpoch, 1);
      expect(state.playbackWanted, isTrue);
      expect(state.volume, closeTo(0.42, 0.0001));
      expect(engineFactory.createCount, 1);
      expect(
        engineFactory.single.loadedUrls,
        orderedEquals([
          'https://cdn.test/audio/one.mp3',
          'https://cdn.test/audio/two.mp3',
        ]),
      );
      expect(engineFactory.single.playCalls, greaterThanOrEqualTo(2));
      expect(engineFactory.single.volumeHistory.last, closeTo(0.42, 0.0001));
    },
  );

  test(
    'stale ended signal after manual selection does not advance the new track',
    () async {
      final engineFactory = FakeHomeAudioEngineFactory();
      final container = ProviderContainer(
        overrides: [
          homeAudioEngineFactoryProvider.overrideWithValue(
            engineFactory.create,
          ),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(
        homeAudioSessionControllerProvider,
        (previous, next) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);

      final controller = container.read(
        homeAudioSessionControllerProvider.notifier,
      );
      await controller.hydrateQueue([
        _item(
          title: 'Track One',
          mediaId: 'media-1',
          url: 'https://cdn.test/audio/one.mp3',
          createdAt: DateTime.utc(2026, 4, 22, 11, 0),
        ),
        _item(
          title: 'Track Two',
          mediaId: 'media-2',
          url: 'https://cdn.test/audio/two.mp3',
          createdAt: DateTime.utc(2026, 4, 22, 10, 0),
        ),
        _item(
          title: 'Track Three',
          mediaId: 'media-3',
          url: 'https://cdn.test/audio/three.mp3',
          createdAt: DateTime.utc(2026, 4, 22, 9, 0),
        ),
      ]);

      await controller.play();
      engineFactory.single.emitProgress(const Duration(seconds: 8));
      await controller.selectIndex(1);

      engineFactory.single.emitEnded();
      await Future<void>.delayed(Duration.zero);

      var state = container.read(homeAudioSessionControllerProvider);
      expect(state.currentIndex, 1);
      expect(
        engineFactory.single.loadedUrls,
        orderedEquals([
          'https://cdn.test/audio/one.mp3',
          'https://cdn.test/audio/two.mp3',
        ]),
      );

      engineFactory.single.emitProgress(const Duration(seconds: 6));
      engineFactory.single.emitEnded();
      await Future<void>.delayed(Duration.zero);

      state = container.read(homeAudioSessionControllerProvider);
      expect(state.currentIndex, 2);
      expect(
        engineFactory.single.loadedUrls,
        orderedEquals([
          'https://cdn.test/audio/one.mp3',
          'https://cdn.test/audio/two.mp3',
          'https://cdn.test/audio/three.mp3',
        ]),
      );
      expect(engineFactory.createCount, 1);
    },
  );

  test(
    'last track stops cleanly without wrap and keeps muted volume state',
    () async {
      final engineFactory = FakeHomeAudioEngineFactory();
      final container = ProviderContainer(
        overrides: [
          homeAudioEngineFactoryProvider.overrideWithValue(
            engineFactory.create,
          ),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(
        homeAudioSessionControllerProvider,
        (previous, next) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);

      final controller = container.read(
        homeAudioSessionControllerProvider.notifier,
      );
      await controller.hydrateQueue([
        _item(
          title: 'Track One',
          mediaId: 'media-1',
          url: 'https://cdn.test/audio/one.mp3',
          createdAt: DateTime.utc(2026, 4, 22, 11, 0),
        ),
        _item(
          title: 'Track Two',
          mediaId: 'media-2',
          url: 'https://cdn.test/audio/two.mp3',
          createdAt: DateTime.utc(2026, 4, 22, 10, 0),
        ),
      ]);

      await controller.setVolume(0.37);
      await controller.setVolume(0);
      await controller.play();
      engineFactory.single.emitProgress(const Duration(seconds: 7));
      engineFactory.single.emitEnded();
      await Future<void>.delayed(Duration.zero);

      var state = container.read(homeAudioSessionControllerProvider);
      expect(state.currentIndex, 1);
      expect(state.volume, 0);
      expect(state.lastNonZeroVolume, closeTo(0.37, 0.0001));
      expect(engineFactory.createCount, 1);

      engineFactory.single.emitProgress(const Duration(seconds: 9));
      engineFactory.single.emitEnded();
      engineFactory.single.emitEnded();
      await Future<void>.delayed(Duration.zero);

      state = container.read(homeAudioSessionControllerProvider);
      expect(state.currentIndex, 1);
      expect(state.isPlaying, isFalse);
      expect(state.activeEpoch, 2);
      expect(state.handledEndedEpoch, 2);
      expect(state.volume, 0);
      expect(state.lastNonZeroVolume, closeTo(0.37, 0.0001));
      expect(
        engineFactory.single.loadedUrls,
        orderedEquals([
          'https://cdn.test/audio/one.mp3',
          'https://cdn.test/audio/two.mp3',
        ]),
      );
      expect(engineFactory.createCount, 1);
    },
  );

  test('duplicate media ids still auto-advance by queue index', () async {
    final engineFactory = FakeHomeAudioEngineFactory();
    final container = ProviderContainer(
      overrides: [
        homeAudioEngineFactoryProvider.overrideWithValue(engineFactory.create),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(
      homeAudioSessionControllerProvider,
      (previous, next) {},
      fireImmediately: true,
    );
    addTearDown(sub.close);

    final controller = container.read(
      homeAudioSessionControllerProvider.notifier,
    );
    await controller.hydrateQueue([
      _item(
        title: 'Duplicate A',
        mediaId: 'duplicate-media',
        url: 'https://cdn.test/audio/a.mp3',
        createdAt: DateTime.utc(2026, 4, 22, 11, 0),
      ),
      _item(
        title: 'Duplicate B',
        mediaId: 'duplicate-media',
        url: 'https://cdn.test/audio/b.mp3',
        createdAt: DateTime.utc(2026, 4, 22, 10, 0),
      ),
    ]);

    await controller.play();
    engineFactory.single.emitProgress(const Duration(seconds: 4));
    engineFactory.single.emitEnded();
    await Future<void>.delayed(Duration.zero);

    final state = container.read(homeAudioSessionControllerProvider);
    expect(state.currentIndex, 1);
    expect(state.currentEntry?.title, 'Duplicate B');
    expect(
      engineFactory.single.loadedUrls,
      orderedEquals([
        'https://cdn.test/audio/a.mp3',
        'https://cdn.test/audio/b.mp3',
      ]),
    );
  });

  test('session controller disposes its single engine when the scope ends', () {
    final engineFactory = FakeHomeAudioEngineFactory();
    final container = ProviderContainer(
      overrides: [
        homeAudioEngineFactoryProvider.overrideWithValue(engineFactory.create),
      ],
    );

    final sub = container.listen(
      homeAudioSessionControllerProvider,
      (previous, next) {},
      fireImmediately: true,
    );
    container.read(homeAudioSessionControllerProvider);

    expect(engineFactory.createCount, 1);

    sub.close();
    container.dispose();

    expect(engineFactory.single.disposeCalls, 1);
  });
}

HomeAudioFeedItem _item({
  required String title,
  required String mediaId,
  required String url,
  required DateTime createdAt,
}) {
  return HomeAudioFeedItem(
    sourceType: HomeAudioSourceType.directUpload,
    title: title,
    teacherId: 'teacher-1',
    createdAt: createdAt,
    media: ResolvedMediaData(
      mediaId: mediaId,
      state: 'ready',
      resolvedUrl: url,
    ),
  );
}

HomeAudioFeedItem _processingItem({
  required String title,
  required String mediaId,
  required DateTime createdAt,
}) {
  return HomeAudioFeedItem(
    sourceType: HomeAudioSourceType.directUpload,
    title: title,
    teacherId: 'teacher-1',
    createdAt: createdAt,
    media: ResolvedMediaData(
      mediaId: mediaId,
      state: 'processing',
      resolvedUrl: null,
    ),
  );
}
