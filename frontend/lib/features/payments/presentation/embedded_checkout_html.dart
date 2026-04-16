import 'dart:convert';

String buildEmbeddedCheckoutHtml({
  required String stripePublishableKey,
  required String clientSecret,
  required String sessionId,
  required String orderId,
}) {
  final publishableKeyLiteral = jsonEncode(stripePublishableKey);
  final clientSecretLiteral = jsonEncode(clientSecret);
  final successUriLiteral = jsonEncode(
    Uri(
      scheme: 'aveliapp',
      host: 'checkout',
      path: '/return',
      queryParameters: {
        if (sessionId.isNotEmpty) 'session_id': sessionId,
        if (orderId.isNotEmpty) 'order_id': orderId,
      },
    ).toString(),
  );
  return '''
<!doctype html>
<html lang="sv">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Aveli betalning</title>
  <style>
    :root {
      color-scheme: light;
      --text: #1f2633;
      --muted: #5d6876;
      --border: #dce8f7;
      --surface: #ffffff;
      --accent: #7aa8f7;
    }
    * { box-sizing: border-box; }
    html, body {
      min-height: 100%;
      margin: 0;
      background: transparent;
      color: var(--text);
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      overflow-x: hidden;
      overflow-y: auto;
    }
    body {
      padding: 0;
      -webkit-overflow-scrolling: touch;
    }
    #checkout-shell {
      width: 100%;
      min-height: 680px;
      border: 0;
      border-radius: 8px;
      background: transparent;
      overflow: visible;
    }
    #checkout {
      width: 100%;
      min-height: 680px;
    }
    #status {
      padding: 18px;
      color: var(--muted);
      font-size: 15px;
      line-height: 1.5;
    }
    #status.error {
      color: #8a2130;
      background: #fff4f6;
      border-bottom: 1px solid #ffd9e0;
    }
  </style>
</head>
<body>
  <main id="checkout-shell" aria-label="Aveli betalning">
    <div id="status">Betalningspanelen laddas.</div>
    <div id="checkout"></div>
  </main>
  <script src="https://js.stripe.com/v3/"></script>
  <script>
    const publishableKey = $publishableKeyLiteral;
    const clientSecret = $clientSecretLiteral;
    const successUri = $successUriLiteral;

    function setStatus(message, isError) {
      const status = document.getElementById('status');
      status.textContent = message;
      status.className = isError ? 'error' : '';
    }

    async function mountCheckout() {
      if (!publishableKey) {
        setStatus('Stripe-konfiguration saknas. Betalningen kan inte starta ännu.', true);
        return;
      }
      if (!clientSecret) {
        setStatus('Betalningssessionen saknas. Försök igen.', true);
        return;
      }
      if (!window.Stripe) {
        setStatus('Betalningspanelen kunde inte laddas. Kontrollera anslutningen och försök igen.', true);
        return;
      }

      try {
        const stripe = window.Stripe(publishableKey);
        const checkout = await stripe.initEmbeddedCheckout({
          fetchClientSecret: async () => clientSecret,
          onComplete: () => {
            window.location.href = successUri;
          }
        });
        document.getElementById('status').remove();
        checkout.mount('#checkout');
      } catch (error) {
        setStatus('Betalningspanelen kunde inte laddas. Försök igen om en stund.', true);
      }
    }

    if (document.readyState === 'complete') {
      mountCheckout();
    } else {
      window.addEventListener('load', mountCheckout, { once: true });
    }
  </script>
</body>
</html>
''';
}
