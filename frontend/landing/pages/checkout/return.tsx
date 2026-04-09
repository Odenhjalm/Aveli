import { useEffect, useMemo, useState } from 'react';
import Head from 'next/head';
import Link from 'next/link';
import { useRouter } from 'next/router';
import styles from '../../styles/CheckoutStatus.module.css';

type Phase = 'processing' | 'error';

const shortValue = (value: string) => {
  if (!value) return '';
  if (value.length <= 10) return value;
  return `${value.slice(0, 6)}...${value.slice(-4)}`;
};

export default function CheckoutReturn() {
  const router = useRouter();
  const [phase, setPhase] = useState<Phase>('processing');
  const [sessionId, setSessionId] = useState('');
  const [orderId, setOrderId] = useState('');
  const [message, setMessage] = useState(
    'Betalningen är skickad. Backend bekräftar köpet via webhook innan åtkomst uppdateras.'
  );
  const [detail, setDetail] = useState<string | null>(
    'Öppna appen eller webbappen och uppdatera ditt konto där. Den här sidan avgör aldrig medlemsstatus eller åtkomst.'
  );

  useEffect(() => {
    if (!router.isReady) return;

    const rawSessionId = router.query.session_id;
    const rawOrderId = router.query.order_id;
    const nextSessionId = Array.isArray(rawSessionId) ? rawSessionId[0] : rawSessionId || '';
    const nextOrderId = Array.isArray(rawOrderId) ? rawOrderId[0] : rawOrderId || '';

    setSessionId(nextSessionId);
    setOrderId(nextOrderId);

    if (!nextSessionId) {
      setPhase('error');
      setMessage('Kunde inte läsa checkout-sessionen.');
      setDetail(
        'Länken saknar session_id. Om du precis betalade, öppna appen och uppdatera ditt konto eller kontakta support med ditt kvitto.'
      );
      return;
    }

    setPhase('processing');
    setMessage(
      'Stripe-redirecten är klar. Nu väntar vi på att backend ska bokföra order och betalning innan åtkomst ändras.'
    );
    setDetail(
      'Ingen åtkomst bekräftas på den här sidan. Fortsätt i appen eller webbappen för att hämta backendens aktuella medlemsstatus.'
    );
  }, [router.isReady, router.query.order_id, router.query.session_id]);

  const appLink = useMemo(() => {
    const params = new URLSearchParams();
    if (sessionId) params.set('session_id', sessionId);
    if (orderId) params.set('order_id', orderId);
    const query = params.toString();
    return query ? `https://app.aveli.app/success?${query}` : 'https://app.aveli.app';
  }, [orderId, sessionId]);

  const statusLabel = phase === 'error' ? 'Behöver din hjälp' : 'Backend bekräftar köpet';

  return (
    <>
      <Head>
        <title>Slutför betalning | Aveli</title>
        <meta
          name="description"
          content="Stripe-redirecten är klar. Aveli uppdaterar åtkomst först efter backendens webhook-bekräftelse."
        />
      </Head>
      <main className={styles.page}>
        <section className={styles.card}>
          <span className={styles.badge}>Stripe Checkout</span>
          <h1 className={styles.title}>Checkout return</h1>
          <p className={styles.lead}>
            Den här sidan visar bara att redirecten kom tillbaka. Backendens order- och webhookflöde
            är fortfarande den enda auktoriteten.
          </p>

          <div className={styles.statusRow}>
            <span className={`${styles.pill} ${phase === 'error' ? styles.error : styles.pending}`}>
              {statusLabel}
            </span>
            {sessionId ? (
              <span className={styles.sessionId}>
                session_id:
                <strong>{shortValue(sessionId)}</strong>
              </span>
            ) : null}
            {orderId ? (
              <span className={styles.sessionId}>
                order_id:
                <strong>{shortValue(orderId)}</strong>
              </span>
            ) : null}
          </div>

          <p className={styles.lead}>{message}</p>
          {detail ? <p className={styles.muted}>{detail}</p> : null}

          <div className={styles.help}>
            <ul className={styles.list}>
              <li>Öppna appen eller webbappen för att uppdatera din backend-session.</li>
              <li>Frontend bekräftar inte medlemsstatus, Stripe-status eller åtkomst här.</li>
              <li>Kontakta support med ditt kvitto och session_id ovan om köpet inte syns senare.</li>
            </ul>
          </div>

          <div className={styles.actions}>
            <Link href="/" className={`${styles.button} ${styles.secondary}`}>
              Till startsidan
            </Link>
            <a className={`${styles.button} ${styles.primary}`} href={appLink} rel="noreferrer">
              Öppna appen
            </a>
          </div>
        </section>
      </main>
    </>
  );
}
