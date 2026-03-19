import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aveli/shared/theme/app_text_colors.dart';
import 'package:aveli/shared/theme/design_tokens.dart';
import 'package:aveli/shared/theme/light_theme.dart';
import 'package:aveli/shared/widgets/brand_header.dart';
import 'package:aveli/shared/widgets/course_intro_badge.dart';
import 'package:aveli/shared/widgets/gradient_text.dart';
import 'package:aveli/shared/widgets/hero_badge.dart';
import 'package:aveli/shared/widgets/semantic_text.dart';

class _StyledTextSegment {
  const _StyledTextSegment(this.text, this.style);

  final String text;
  final TextStyle? style;
}

void _collectStyledTextSegments(
  InlineSpan span,
  List<_StyledTextSegment> segments, {
  TextStyle? inheritedStyle,
}) {
  if (span is! TextSpan) {
    return;
  }

  final effectiveStyle = inheritedStyle?.merge(span.style) ?? span.style;
  final text = span.text;
  if (text != null && text.isNotEmpty) {
    segments.add(_StyledTextSegment(text, effectiveStyle));
  }

  for (final child in span.children ?? const <InlineSpan>[]) {
    _collectStyledTextSegments(child, segments, inheritedStyle: effectiveStyle);
  }
}

List<TextStyle?> _textStylesForText(WidgetTester tester, String target) {
  final segments = <_StyledTextSegment>[];
  final richTextFinder = find.byType(RichText);
  for (final richText in tester.widgetList<RichText>(richTextFinder)) {
    _collectStyledTextSegments(richText.text, segments);
  }
  return [
    for (final segment in segments)
      if (segment.text.contains(target)) segment.style,
  ];
}

Matcher _hasTextColor(Color color) {
  return everyElement(
    predicate<TextStyle?>(
      (style) => style?.color == color,
      'text resolves to $color',
    ),
  );
}

class _TextColorContractHarness extends StatefulWidget {
  const _TextColorContractHarness();

  @override
  State<_TextColorContractHarness> createState() =>
      _TextColorContractHarnessState();
}

class _TextColorContractHarnessState extends State<_TextColorContractHarness> {
  bool _showLanding = false;

  @override
  Widget build(BuildContext context) {
    final theme = _showLanding
        ? buildLightTheme(forLanding: true)
        : buildLightTheme();

    return MaterialApp(
      theme: theme,
      home: Navigator(
        pages: [
          MaterialPage<void>(
            child: _NormalContractPage(
              onOpenLanding: () => setState(() => _showLanding = true),
            ),
          ),
          if (_showLanding)
            const MaterialPage<void>(child: _LandingContractPage()),
        ],
        onDidRemovePage: (page) {
          if (_showLanding) {
            setState(() => _showLanding = false);
          }
        },
      ),
    );
  }
}

class _NormalContractPage extends StatelessWidget {
  const _NormalContractPage({required this.onOpenLanding});

  final VoidCallback onOpenLanding;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SectionHeading('Vanlig sida'),
            const SizedBox(height: 12),
            GradientText('Lanktext', style: style),
            const SizedBox(height: 12),
            const CourseIntroBadge(
              label: 'Introduktion lank',
              variant: CourseIntroBadgeVariant.link,
            ),
            const SizedBox(height: 12),
            const BrandWordmark(),
            const SizedBox(height: 12),
            FilledButton(onPressed: () {}, child: const Text('Hemknapp')),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () {},
              child: const Text('Outline knapp'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onOpenLanding,
              child: const Text('Oppna landing'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LandingContractPage extends StatelessWidget {
  const _LandingContractPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const HeroHeading(
              leading: 'Upptack din andliga',
              gradientWord: 'resa',
            ),
            const SizedBox(height: 12),
            const SectionHeading('Larare'),
            const SizedBox(height: 12),
            const MetaText('Mot certifierade larare.'),
            const SizedBox(height: 12),
            const HeroBadge(text: 'Sveriges ledande plattform'),
            const SizedBox(height: 12),
            const BrandWordmark(),
            const SizedBox(height: 12),
            const CourseIntroBadge(label: 'Introduktion badge'),
            const SizedBox(height: 12),
            FilledButton(onPressed: () {}, child: const Text('Bli medlem')),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {},
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: const Text('Logga in'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Tillbaka'),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  testWidgets(
    'keeps app text black across navigation while preserving the landing hero exception',
    (tester) async {
      await tester.pumpWidget(const _TextColorContractHarness());

      expect(
        _textStylesForText(tester, 'Vanlig sida'),
        _hasTextColor(AppTextColor.body),
      );
      expect(
        _textStylesForText(tester, 'Lanktext'),
        _hasTextColor(AppTextColor.body),
      );
      expect(
        _textStylesForText(tester, 'Introduktion lank'),
        _hasTextColor(Colors.white),
      );
      expect(find.byType(ShaderMask), findsOneWidget);
      expect(
        _textStylesForText(tester, 'Hemknapp'),
        _hasTextColor(DesignTokens.heroTextColor),
      );
      expect(
        _textStylesForText(tester, 'Outline knapp'),
        _hasTextColor(AppTextColor.body),
      );
      expect(
        _textStylesForText(tester, 'Oppna landing'),
        _hasTextColor(AppTextColor.body),
      );

      await tester.tap(find.text('Oppna landing'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        _textStylesForText(tester, 'Larare'),
        _hasTextColor(AppTextColor.body),
      );
      expect(
        _textStylesForText(tester, 'Mot certifierade larare.'),
        _hasTextColor(AppTextColor.body),
      );
      expect(
        _textStylesForText(tester, 'Sveriges ledande plattform'),
        _hasTextColor(Colors.white),
      );
      expect(
        _textStylesForText(tester, 'Introduktion badge'),
        _hasTextColor(Colors.white),
      );
      expect(
        _textStylesForText(tester, 'Bli medlem'),
        _hasTextColor(DesignTokens.heroTextColor),
      );
      expect(
        _textStylesForText(tester, 'Logga in'),
        _hasTextColor(Colors.white),
      );

      final heroLeadingStyles = _textStylesForText(
        tester,
        'Upptack din andliga',
      );
      final heroGradientStyles = _textStylesForText(tester, 'resa');

      expect(heroLeadingStyles, isNotEmpty);
      expect(heroGradientStyles, isNotEmpty);
      expect(heroLeadingStyles, _hasTextColor(DesignTokens.heroTextColor));
      expect(heroGradientStyles, _hasTextColor(DesignTokens.heroTextColor));

      await tester.tap(find.text('Tillbaka'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        _textStylesForText(tester, 'Vanlig sida'),
        _hasTextColor(AppTextColor.body),
      );
      expect(
        _textStylesForText(tester, 'Lanktext'),
        _hasTextColor(AppTextColor.body),
      );
      expect(
        _textStylesForText(tester, 'Introduktion lank'),
        _hasTextColor(Colors.white),
      );
      expect(
        _textStylesForText(tester, 'Hemknapp'),
        _hasTextColor(DesignTokens.heroTextColor),
      );
      expect(
        _textStylesForText(tester, 'Outline knapp'),
        _hasTextColor(AppTextColor.body),
      );
      expect(
        _textStylesForText(tester, 'Oppna landing'),
        _hasTextColor(AppTextColor.body),
      );
    },
  );
}
