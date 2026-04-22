import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aveli/core/errors/app_failure.dart';
import 'package:aveli/features/admin/application/admin_observatorium_provider.dart';
import 'package:aveli/features/community/application/community_providers.dart';
import 'package:aveli/features/community/data/admin_repository.dart';
import 'package:aveli/features/media_control_plane/admin/media_control_plane_providers.dart';
import 'package:aveli/features/media_control_plane/data/media_control_plane_repository.dart';
import '../helpers/admin_test_fixtures.dart';

class _MockAdminRepository extends Mock implements AdminRepository {}

class _MockMediaControlPlaneRepository extends Mock
    implements MediaControlPlaneRepository {}

void main() {
  late _MockAdminRepository adminRepository;
  late _MockMediaControlPlaneRepository mediaRepository;

  setUp(() {
    adminRepository = _MockAdminRepository();
    mediaRepository = _MockMediaControlPlaneRepository();
  });

  test(
    'adminSettingsProvider parses canonical metrics and priorities',
    () async {
      when(
        () => adminRepository.fetchSettings(),
      ).thenAnswer((_) async => sampleAdminSettingsPayload());

      final container = ProviderContainer(
        overrides: [adminRepositoryProvider.overrideWithValue(adminRepository)],
      );
      addTearDown(container.dispose);

      final state = await container.read(adminSettingsProvider.future);

      expect(state.metrics.totalUsers, 42);
      expect(state.metrics.paidOrders30d, 8);
      expect(state.priorities, hasLength(2));
      expect(state.priorities.first.displayName, 'Aveli Teacher');
      expect(state.priorities.first.priority, 1);
    },
  );

  test(
    'adminObservatoriumProvider derives the six observatorium cards',
    () async {
      when(
        () => adminRepository.fetchSettings(),
      ).thenAnswer((_) async => sampleAdminSettingsPayload());
      when(
        () => mediaRepository.fetchHealth(),
      ).thenAnswer((_) async => sampleMediaHealthPayload());

      final container = ProviderContainer(
        overrides: [
          adminRepositoryProvider.overrideWithValue(adminRepository),
          mediaControlPlaneRepositoryProvider.overrideWithValue(
            mediaRepository,
          ),
        ],
      );
      addTearDown(container.dispose);

      final state = await container.read(adminObservatoriumProvider.future);

      expect(state.cards.map((card) => card.id), [
        'notifications',
        'auth-system',
        'learning-system',
        'system-health',
        'payments',
        'media-control-plane',
      ]);
      expect(state.statusChipLabel, 'All systems nominal');
      expect(state.isNominal, isTrue);
      expect(
        state.cards
            .firstWhere((card) => card.id == 'auth-system')
            .lines
            .contains('42 total users'),
        isTrue,
      );
      expect(
        state.cards
            .firstWhere((card) => card.id == 'media-control-plane')
            .summary,
        contains('Status OK'),
      );
    },
  );

  test(
    'adminObservatoriumProvider keeps partial data when media health fails',
    () async {
      when(
        () => adminRepository.fetchSettings(),
      ).thenAnswer((_) async => sampleAdminSettingsPayload());
      when(
        () => mediaRepository.fetchHealth(),
      ).thenThrow(UnexpectedFailure(message: 'Media offline'));

      final container = ProviderContainer(
        overrides: [
          adminRepositoryProvider.overrideWithValue(adminRepository),
          mediaControlPlaneRepositoryProvider.overrideWithValue(
            mediaRepository,
          ),
        ],
      );
      addTearDown(container.dispose);

      final state = await container.read(adminObservatoriumProvider.future);

      expect(state.settingsError, isNull);
      expect(state.mediaError, 'Media offline');
      expect(state.isNominal, isFalse);
      expect(state.statusChipLabel, 'Partial system visibility');
      expect(
        state.cards.firstWhere((card) => card.id == 'system-health').summary,
        contains('degraded'),
      );
    },
  );
}
