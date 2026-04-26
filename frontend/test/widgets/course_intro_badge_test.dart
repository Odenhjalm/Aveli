import 'package:aveli/shared/widgets/course_intro_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'CourseIntroBadge keeps Introduktion on one line in narrow slots',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));

      for (final width in <double>[36, 64, 92, 320]) {
        await tester.binding.setSurfaceSize(Size(width, 80));
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: double.infinity,
                child: CourseIntroBadge(label: 'Introduktion'),
              ),
            ),
          ),
        );

        final label = tester.widget<Text>(find.text('Introduktion'));
        expect(label.maxLines, 1);
        expect(label.softWrap, isFalse);
        expect(label.overflow, TextOverflow.ellipsis);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('CourseIntroBadge uses compact content-driven badge sizing', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: CourseIntroBadge(label: 'Introduktion')),
        ),
      ),
    );

    final badgeSize = tester.getSize(find.byType(ClipRRect));
    final textSize = tester.getSize(find.text('Introduktion'));

    expect(badgeSize.width - textSize.width, closeTo(12, 0.1));
    expect(badgeSize.height - textSize.height, closeTo(6, 0.1));
    expect(tester.takeException(), isNull);
  });
}
