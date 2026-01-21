import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_logo.dart';

/// Baslayout som sätter stor logga högst upp på varje sida.
class BasePage extends StatelessWidget {
  const BasePage({super.key, required this.child, this.logoSize = 150});

  final Widget child;
  final double logoSize;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final hasBoundedHeight = constraints.maxHeight.isFinite;
        final body = hasBoundedHeight
            ? Expanded(child: child)
            : Flexible(fit: FlexFit.loose, child: child);
        final showLogo = logoSize > 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showLogo) AppLogo(size: logoSize),
            body,
            const _LegalLinks(),
          ],
        );
      },
    );
  }
}

class _LegalLinks extends StatelessWidget {
  const _LegalLinks();

  static final Uri _termsUri =
      Uri.parse('https://aveli.app/aveli-terms-of-service/');
  static final Uri _privacyUri = Uri.parse('https://aveli.app/privacy-policy/');
  static final Uri _dataDeletionUri =
      Uri.parse('https://aveli.app/user-data-deletion-instructions/');

  @override
  Widget build(BuildContext context) {
    final bottomPadding = _bottomNavPadding(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomPadding),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 4,
        children: [
          _LegalLinkButton(label: 'Terms of Service', uri: _termsUri),
          _LegalLinkButton(label: 'Privacy Policy', uri: _privacyUri),
          _LegalLinkButton(label: 'Data Deletion', uri: _dataDeletionUri),
        ],
      ),
    );
  }
}

class _LegalLinkButton extends StatelessWidget {
  const _LegalLinkButton({required this.label, required this.uri});

  final String label;
  final Uri uri;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: TextButton.styleFrom(foregroundColor: Colors.black),
      onPressed: () async {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      },
      child: Text(label),
    );
  }
}

double _bottomNavPadding(BuildContext context) {
  final scaffold = Scaffold.maybeOf(context);
  final bottomNav = scaffold?.widget.bottomNavigationBar;
  if (scaffold == null || bottomNav == null || !scaffold.widget.extendBody) {
    return 0;
  }

  if (bottomNav is NavigationBar) {
    return bottomNav.height ?? NavigationBarTheme.of(context).height ?? 80;
  }

  if (bottomNav is BottomNavigationBar) {
    return kBottomNavigationBarHeight;
  }

  if (bottomNav is PreferredSizeWidget) {
    return bottomNav.preferredSize.height;
  }

  return kBottomNavigationBarHeight;
}
