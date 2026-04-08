
> **Mål:** Centrera personens huvud i bakgrundsbilden exakt under hero‑loggan, stabilt på alla breakpoints.
> **Gör så här – utan diffar, leverera fullständig kod:**
>
> 1. **Öppna** filen som definierar `FullBleedBackground` (sök `class FullBleedBackground` i `lib/**`).
>
> 2. **Utöka API:t** med fokaljustering:
>
>    ```dart
>    class FullBleedBackground extends StatefulWidget {
>      const FullBleedBackground({
>        super.key,
>        required this.image,
>        this.yOffset = 0,
>        this.scale = 1.0,
>        this.topOpacity = 0.0,
>        this.sideVignette = 0.0,
>        this.overlayColor,
>        this.child,
>        // NYTT:
>        this.focalX,              // 0..1 (vänster..höger) – om satt används pixel-translation
>        this.pixelNudgeX = 0.0,   // extra finjustering i px (+ vänster, – höger)
>      });
>      final ImageProvider image;
>      final double yOffset, scale, topOpacity, sideVignette;
>      final Color? overlayColor;
>      final Widget? child;
>      // NYTT:
>      final double? focalX;
>      final double pixelNudgeX;
>      @override State<FullBleedBackground> createState() => _FBBState();
>    }
>    ```
>
> 3. **Implementera fokalstyrd layout** i `_FBBState.build`: räkna ut hur stor bilden blir med `BoxFit.cover` och flytta den i **pixlar** så att `focalX` hamnar i viewportens mitt.
>
>    ```dart
>    class _FBBState extends State<FullBleedBackground> {
>      Size? _imgSize; // i pixlar
>      @override
>      void didChangeDependencies() {
>        super.didChangeDependencies();
>        // Läs bildens råa dimensioner en gång
>        final stream = widget.image.resolve(createLocalImageConfiguration(context));
>        stream.addListener(ImageStreamListener((info, _) {
>          final s = Size(info.image.width.toDouble(), info.image.height.toDouble());
>          if (_imgSize != s && mounted) setState(() => _imgSize = s);
>        }));
>      }
>      @override
>      Widget build(BuildContext context) {
>        return LayoutBuilder(builder: (context, c) {
>          final Wc = c.maxWidth, Hc = c.maxHeight;
>          if (_imgSize == null) {
>            // fallback: vanlig alignment tills vi har dimensioner
>            return _PlainAlignedBackground(widget: widget);
>          }
>          final Wi = _imgSize!.width, Hi = _imgSize!.height;
>          // cover-skalning * extra skala
>          final s = (Wc / Wi > Hc / Hi ? Wc / Wi : Hc / Hi) * widget.scale;
>          final Wd = Wi * s;               // visad bildbredd i px
>          final Hd = Hi * s;               // visad bildhöjd i px
>          // Om ingen fokalpunkt angiven -> vanlig aligned
>          if (widget.focalX == null) {
>            return _PlainAlignedBackground(widget: widget);
>          }
>          final fx = widget.focalX!.clamp(0.0, 1.0);
>          // dx så att fx*Wd hamnar i mitten av containern
>          final dx = (Wc / 2) - (fx * Wd) + widget.pixelNudgeX;
>          // y‑offset behålls (widget.yOffset)
>          final dy = widget.yOffset;
>          return Stack(fit: StackFit.expand, children: [
>            // overflow tillåts eftersom Wd/Hd kan vara större än containern
>            OverflowBox(
>              minWidth: Wd, maxWidth: Wd, minHeight: Hd, maxHeight: Hd,
>              alignment: Alignment.topLeft,
>              child: Transform.translate(
>                offset: Offset(dx, dy),
>                child: Image(image: widget.image, width: Wd, height: Hd, fit: BoxFit.cover, filterQuality: FilterQuality.high),
>              ),
>            ),
>            if (widget.overlayColor != null)
>              Container(color: widget.overlayColor!.withOpacity(1.0)),
>            // top scrim
>            IgnorePointer(child: DecoratedBox(
>              decoration: BoxDecoration(
>                gradient: LinearGradient(
>                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
>                  colors: [Colors.black.withOpacity(widget.topOpacity), Colors.transparent],
>                ),
>              ),
>            )),
>            if (widget.child != null) widget.child!,
>          ]);
>        });
>      }
>    }
>    // Enkel fallback med gammal alignment-tolkning
>    class _PlainAlignedBackground extends StatelessWidget {
>      const _PlainAlignedBackground({required this.widget});
>      final FullBleedBackground widget;
>      @override
>      Widget build(BuildContext context) {
>        return DecoratedBox(
>          decoration: BoxDecoration(
>            image: DecorationImage(
>              image: widget.image,
>              fit: BoxFit.cover,
>              alignment: Alignment.topCenter,
>            ),
>          ),
>          child: widget.child,
>        );
>      }
>    }
>    ```
>
> 4. **Öppna** `lib/ui/pages/landing_page.dart` och **använd fokal‑API:t** i `FullBleedBackground` i stället för `alignment`. Sätt första gissning för huvudets andel från vänster (`focalX`) och ge en liten pixel‑knuff:
>
>    ```dart
>    body: FullBleedBackground(
>      image: _bg,
>      focalX: 0.58,          // ~58% från vänster (justera 0.55–0.62 tills perfekt)
>      pixelNudgeX: -6,       // negativt = lite mer åt höger
>      topOpacity: topScrimOpacity,
>      yOffset: y,
>      scale: imgScale,
>      sideVignette: 0,
>      overlayColor: isLightMode ? const Color(0xFFFFE2B8).withValues(alpha: 0.10) : null,
>      child: Stack( /* oförändrat */ ),
>    ),
>    ```
>
> 5. **(Valfri debug)**: Rita en tunn vertikal linje i mitten (Center‑guide) i `landing_page.dart` för att kontrollera att huvudet ligger exakt under loggan:
>
>    ```dart
>    Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _CenterGuidePainter()))),
>    // …
>    class _CenterGuidePainter extends CustomPainter {
>      @override void paint(Canvas c, Size s) {
>        final p = Paint()..color = Colors.white.withOpacity(.15)..strokeWidth = 1;
>        c.drawLine(Offset(s.width/2, 0), Offset(s.width/2, s.height), p);
>      }
>      @override bool shouldRepaint(_) => false;
>    }
>    ```
>
> **Krav:** Lämna övriga parametrar orörda, inga diffar – leverera kompletta, körbara filversioner. Lägg kommentarer som förklarar riktningen (`pixelNudgeX < 0 ⇒ mer åt höger`).
> **Efter:** Kör appen. Finjustera `focalX` i steg om 0.01 och `pixelNudgeX` i steg om 2–4 px tills huvudet sitter exakt under loggan på desktop och mobil.

---
