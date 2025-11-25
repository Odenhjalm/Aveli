import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum EnvStatus { ok, missing }

@immutable
class EnvInfo {
  const EnvInfo({required this.status, this.missingKeys = const <String>[]});

  final EnvStatus status;
  final List<String> missingKeys;

  bool get hasIssues => status != EnvStatus.ok;
}

const EnvInfo envInfoOk = EnvInfo(status: EnvStatus.ok);

final envInfoProvider = StateProvider<EnvInfo>((_) => envInfoOk);

extension EnvInfoX on EnvInfo {
  String get message {
    if (missingKeys.isEmpty) {
      return 'API-konfiguration saknas.';
    }
    return 'Miljövariabler saknas: ${missingKeys.join(', ')}.';
  }
}
