# Flutter MVP-klient

Den nya `lib/mvp/`-modulen innehåller en fristående demo som pratar direkt med MVP-backenden (`app.mvp.main`).

## Bas-URL per plattform

| Plattform | Bas-URL |
| --- | --- |
| Android emulator | `http://10.0.2.2:8080` |
| iOS/desktop/web | `http://127.0.0.1:8080` |
| Override | sätt `--dart-define=MVP_BASE_URL=http://192.168.1.10:8080` |

`MvpAppConfig.resolveBaseUrl()` hanterar ovanstående. För Android emulator används `10.0.2.2`, för övriga plattformar `127.0.0.1` och `dart-define` vinner alltid.

## Snabbstart

```bash
flutter run -d chrome --dart-define=MVP_BASE_URL=http://127.0.0.1:8080 \
  -t lib/mvp/mvp_app.dart
```

### ApiClient-exempel

```dart
final client = MvpApiClient();
await client.login(email: 'demo@aveli.local', password: 'secret');
final services = await client.listActiveServices();
```

### LiveKit

Sidan "Live" i `MvpApp` hämtar token via `/sfu/token`. Lägg `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET` och `LIVEKIT_WS_URL` i backend `.env` innan du testar.
