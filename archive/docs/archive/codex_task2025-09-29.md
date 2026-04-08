MÅL
A) Flytta badgen "Sveriges ledande plattform för andlig utveckling" så att den ligger strax ovanför sektionen "Populära kurser".
B) Lägg en stor, centrerad logga högst upp på **varje** screen i appen.
C) Gör loggan större (ca 140–160 px) och skarp på web.

TILLVÄGAGÅNGSSÄTT (GENOMFÖR ALLA STEG)

1) Skapa gemensam logga-widget + baslayout
- Lägg till fil: lib/widgets/app_logo.dart
----------------------------------------------------------------
import 'package:flutter/material.dart';

class AppLogo extends StatelessWidget {
  final double size;
  const AppLogo({super.key, this.size = 150});

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.only(top: 18.0, bottom: 12.0),
        child: Image.asset(
          'assets/loggo_clea.png', // byt till korrekt path om annorlunda
          height: size,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          cacheWidth: (size * dpr).round(),
        ),
      ),
    );
  }
}
----------------------------------------------------------------

- Lägg till fil: lib/widgets/base_page.dart
----------------------------------------------------------------
import 'package:flutter/material.dart';
import 'app_logo.dart';

/// Baslayout som sätter stor logga högst upp på varje sida.
class BasePage extends StatelessWidget {
  final Widget child;
  final double logoSize;
  const BasePage({super.key, required this.child, this.logoSize = 150});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AppLogo(size: logoSize),
        Expanded(child: child),
      ],
    );
  }
}
----------------------------------------------------------------

2) Använd BasePage på ALLA skärmar
- Öppna varje *Page/Screen* som idag returnerar `Scaffold(body: ...)`.
- Byt ut body till:
    body: BasePage(
      logoSize: 150, // justerbar 140–160
      child: <SIDANS_BEFINTLIGA_INNEHÅLL>,
    ),
- Om en sida redan har en Column/ScrollView, lägg den som `child:` oförändrat.
- Sidor med egen AppBar-logga: behåll AppBar men ta bort stora loggan där; låt den stora loggan komma från BasePage (i body). Leading-ikon kan vara liten eller tom.

3) Flytta badgen på LANDING/HOME till ovanför "Populära kurser"
- Sök i projektet efter texten: "Sveriges ledande plattform för andlig utveckling".
- Den renderas idag nära hero-rubriken. Vi ska flytta den till direkt ovanför "Populära kurser".
- I filen som innehåller landningssidan (t.ex. lib/features/landing/landing_page.dart):
  a) Identifiera Column/Scroll/Sliver där sektionen "Populära kurser" börjar (sök efter "Populära kurser", "Populara kurser", eller nyckel i l10n).
  b) Flytta badgens widget (Chip/GlassChip/Container) från hero-stacken till att ligga precis före "Populära kurser"-rubriken i samma Column/Sliver.
  c) Ge badgen vertikala mellanrum:
      const SizedBox(height: 16),
      <BADGE_WIDGET>,
      const SizedBox(height: 8),
  d) Ta bort ev. Positioned/Stack-placering av badgen i hero så den inte visas dubbelt.

- Om badgen idag använder BackdropFilter/glass: behåll samma widget, endast ny placering.
- Säkerställ att hero-rubriken/CTA inte har extra top-padding som förväntade badgen; justera om nödvändigt (t.ex. minska hero-top padding med 12–16 px).

4) Finjustera rubrikblock på LANDING
- Hero-block får inte krocka med AppLogo (som nu visas högst upp).
- Sänk hero-rubrikens top-padding med ~AppLogo-höjden minus SafeArea (ex: om tidigare `EdgeInsets.only(top: 140)`, minska till 80–100).
- Se till att CTA-knapparnas rad ligger kvar under rubriken (ingen överlapp).

5) Kvalitet & responsivitet
- För sidor med lång scroll: BasePage’s `Expanded(child: …)` ska innehålla `SingleChildScrollView` som det var tidigare, ingen funktionalitet får förloras.
- Stora skärmar: AppLogo får maxbredd via höjd-styrning, ingen horisontell stretch.
- `flutter analyze` ska vara grön; lägg till nödvändiga imports:
    import 'widgets/base_page.dart';
    import 'widgets/app_logo.dart';

6) Verifiering
- Starta appen, gå igenom: Landing/Home, Login, Settings, Kurslistor, Tjänster, etc.
- Överst på **alla** sidor syns nu en stor centrerad logga (≈150 px).
- På Landing ligger badgen "Sveriges ledande plattform…" direkt ovanför rubriken "Populära kurser".
- Inget dubblerat badge-element i hero. Layouten är stabil på mobil/web/desktop.

COMMIT-TEXT
feat(ui): global top-centered AppLogo on all screens + move “Sveriges ledande…” badge above “Populära kurser”

## Status 2025-09-30
- AppLogo + BasePage inlagda som gemensam layoutkomponent och kopplade till AppScaffold.
- Samtliga auth-, community-, kurs-, studio- och legacy-sidor uppdaterade att använda BasePage/Top-logo.
- Landing badge "Sveriges ledande…" flyttad ovanför "Populära kurser" och hero-spacing justerad.
