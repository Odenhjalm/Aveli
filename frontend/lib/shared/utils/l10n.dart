import 'package:flutter/widgets.dart';
import 'package:wisdom/l10n/app_localizations.dart';

extension BuildContextL10n on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this)!;
}
