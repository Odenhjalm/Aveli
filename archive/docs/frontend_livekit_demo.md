# LiveKit demo i Flutter

Den nya LiveKit-integrationen finns i `LiveKitDemoPage` och använder `/sfu/token`
endpointen i backenden för att hämta `ws_url` och `token`.

## Krav

- Sätt följande nycklar i `.env`:

```env
LIVEKIT_API_KEY=...
LIVEKIT_API_SECRET=...
LIVEKIT_WS_URL=wss://your-livekit-domain
LIVEKIT_API_URL=https://your-livekit-domain
```

- Starta backend (FastAPI + Postgres) och se till att seedade seminariet
  `99999999-9999-4999-8999-999999999999` finns (ingår i `002_seed_dev.sql`).
- På Android/iOS/macOS måste appen ha kamera- och mikrofonbehörighet. Ge tillgång
  första gången prompten visas – den nya pre-join-vyn låser previewn om behörighet saknas.

## Kör demo

1. `flutter run`
2. Navigera till `http://localhost:3000/#/sfu-demo` (web) eller `/sfu-demo`
   via router.
3. Klicka “Anslut” – sidan visar status, `ws_url`, token (trunkerat) och
   eventuella fel. Vid lyckad anslutning uppdateras statusen till “Ansluten”.

Härifrån kan du bygga vidare (lista deltagare via `room.remoteParticipants`,
publicera media osv.).
