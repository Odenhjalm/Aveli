# SFU / LiveKit – MVP

## Miljövariabler

Lägg följande i `.env` (backend):

```
LIVEKIT_API_KEY=
LIVEKIT_API_SECRET=
LIVEKIT_WS_URL=wss://<your-instance>.livekit.cloud
LIVEKIT_API_URL=https://<your-instance>.livekit.cloud
LIVEKIT_WEBHOOK_SECRET=<optional>
```

Utan nycklar svarar `/sfu/token` med 503.

## Token-endpoint

`POST /sfu/token` tar `{ "seminar_id": "uuid" }` och returnerar `{ "ws_url", "token" }`. Endpointen kollar att användaren antingen är host eller registrerad deltagare.

## Flutter-klient

`MvpLiveKitPage` i `lib/mvp/widgets/mvp_livekit_page.dart` låter dig ange ett seminarie-ID och ansluter via `livekit_client`. När token hämtas visas deltagarlistan och du kan koppla från med ett klick.

## QA

1. Skapa seminarium via studio/admin och registrera en användare.
2. Logga in med Flutter `MvpApp` och öppna fliken **Live**.
3. Ange seminarie-ID → tryck **Anslut**. Om allt är korrekt visas en lokal deltagare i listan.
