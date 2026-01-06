import { useEffect, useRef, useState } from 'react';
import Head from 'next/head';
import Link from 'next/link';
import { useRouter } from 'next/router';
import styles from '../../styles/CheckoutStatus.module.css';

type MembershipRecord = {
  status?: string | null;
  plan_interval?: string | null;
  stripe_subscription_id?: string | null;
};

type MembershipResponse = {
  membership: MembershipRecord | null;
};

type SessionStatusResponse = {
  ok: boolean;
  session_id: string;
  mode?: string | null;
  payment_status?: string | null;
  subscription_status?: string | null;
  membership_status?: string | null;
  updated_at?: string | null;
  poll_after_ms?: number;
};

type Phase = 'pending' | 'success' | 'error' | 'unauthorized';

const POLL_INTERVAL_MS = 2000;
const POLL_TIMEOUT_MS = 30000;

const resolveApiBase = () => {
  const envBase = process.env.NEXT_PUBLIC_API_BASE_URL?.replace(/\/$/, '');
  if (envBase) return envBase;
  if (typeof window !== 'undefined') {
    return window.location.origin.replace(/\/$/, '');
  }
  return '';
};

const shortSessionId = (sessionId: string) => {
  if (!sessionId) return '';
  if (sessionId.length <= 10) return sessionId;
  return `${sessionId.slice(0, 6)}…${sessionId.slice(-4)}`;
};

const isActive = (status: string | null | undefined) => status === 'active' || status === 'trialing';
const isPending = (status: string | null | undefined) =>
  status === null || status === undefined || status === 'incomplete' || status === 'processing';

export default function CheckoutReturn() {
  const router = useRouter();
  const [sessionId, setSessionId] = useState('');
  const [phase, setPhase] = useState<Phase>('pending');
  const [message, setMessage] = useState('Bearbetar betalningen…');
  const [detail, setDetail] = useState<string | null>(null);
  const [membershipStatus, setMembershipStatus] = useState<string | null>(null);
  const [attempts, setAttempts] = useState(0);
  const [remainingMs, setRemainingMs] = useState(POLL_TIMEOUT_MS);
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const lastStatusRef = useRef<string | null>(null);

  useEffect(() => {
    if (!router.isReady) return;

    const rawId = router.query.session_id;
    const id = Array.isArray(rawId) ? rawId[0] : rawId || '';
    setSessionId(id);

    if (!id) {
      setPhase('error');
      setMessage('Kunde inte läsa checkout-sessionen.');
      setDetail('Länken saknar session_id. Om du precis betalat, kontakta support med ditt kvitto.');
      return;
    }

    let cancelled = false;
    const startedAt = Date.now();
    const apiBase = resolveApiBase();
    const membershipUrl = apiBase ? `${apiBase}/api/me/membership` : '/api/me/membership';
    const sessionStatusUrl = apiBase
      ? `${apiBase}/api/billing/session-status?session_id=${encodeURIComponent(id)}`
      : `/api/billing/session-status?session_id=${encodeURIComponent(id)}`;

    const fetchMembershipStatus = async () => {
      const response = await fetch(membershipUrl, { credentials: 'include' });
      if (response.status === 401 || response.status === 403) {
        setPhase('unauthorized');
        setMessage('Logga in för att slutföra betalningen.');
        setDetail('Öppna Aveli-appen eller webbklienten, logga in och försök igen.');
        return null;
      }
      if (!response.ok) {
        throw new Error(`Membership fetch failed: ${response.status}`);
      }
      const payload = (await response.json()) as MembershipResponse;
      return payload?.membership?.status ?? null;
    };

    const poll = async () => {
      if (cancelled) return;
      const elapsed = Date.now() - startedAt;
      setRemainingMs(Math.max(0, POLL_TIMEOUT_MS - elapsed));

      try {
        let status: string | null = null;

        if (id) {
          const response = await fetch(sessionStatusUrl);
          if (cancelled) return;

          if (response.status === 401 || response.status === 403) {
            setPhase('unauthorized');
            setMessage('Logga in för att slutföra betalningen.');
            setDetail('Öppna Aveli-appen eller webbklienten, logga in och försök igen.');
            return;
          }

          if (response.status === 404) {
            setPhase('error');
            setMessage('Hittade inte checkout-sessionen.');
            setDetail('Kontrollera länken eller kontakta supporten med ditt kvitto.');
            return;
          }

          if (!response.ok) {
            throw new Error(`Session-status failed: ${response.status}`);
          }

          const payload = (await response.json()) as SessionStatusResponse;
          const sessionMembershipStatus =
            payload.membership_status === 'unknown' ? null : payload.membership_status;
          status = sessionMembershipStatus || payload.subscription_status || null;
          lastStatusRef.current = status;
          setMembershipStatus(status);

          if (isActive(status)) {
            setPhase('success');
            setMessage('Betalningen är bekräftad.');
            setDetail('Ditt medlemskap är aktivt. Du kan stänga denna flik och fortsätta i appen.');
            return;
          }

          if (!status && payload.payment_status === 'paid') {
            try {
              status = await fetchMembershipStatus();
              if (status) {
                setMembershipStatus(status);
              }
            } catch {
              // ignore transient membership errors
            }
          }
        } else {
          status = await fetchMembershipStatus();
          lastStatusRef.current = status;
          setMembershipStatus(status);
        }

        if (isActive(status)) {
          setPhase('success');
          setMessage('Betalningen är bekräftad.');
          setDetail('Ditt medlemskap är aktivt. Du kan stänga denna flik och fortsätta i appen.');
          return;
        }

        if (isPending(status) && elapsed < POLL_TIMEOUT_MS) {
          setPhase('pending');
          setMessage('Vi bekräftar betalningen...');
          timerRef.current = setTimeout(poll, POLL_INTERVAL_MS);
          return;
        }

        if (elapsed < POLL_TIMEOUT_MS) {
          setPhase('pending');
          setMessage('Vi väntar på att Stripe ska bekräfta betalningen…');
          timerRef.current = setTimeout(poll, POLL_INTERVAL_MS);
          return;
        }

        setPhase('error');
        setMessage('Betalningen kunde inte bekräftas ännu.');
        setDetail(
          status
            ? `Senast kända status: ${status}. Kontrollera ditt kvitto eller försök igen.`
            : 'Ingen medlemskapsdata hittades ännu. Om du precis betalade kan det hjälpa att öppna appen och uppdatera.'
        );
      } catch (error) {
        if (cancelled) return;
        if (elapsed < POLL_TIMEOUT_MS) {
          setPhase('pending');
          setMessage('Återförsöker att hämta status…');
          timerRef.current = setTimeout(poll, POLL_INTERVAL_MS);
          return;
        }
        setPhase('error');
        setMessage('Tidsgräns för bekräftelse.');
        setDetail(
          lastStatusRef.current
            ? `Senast kända status: ${lastStatusRef.current}.`
            : 'Vi fick inget svar i tid. Kontrollera kvittot i Stripe och försök igen.'
        );
      }
    };

    poll();

    return () => {
      cancelled = true;
      if (timerRef.current) {
        clearTimeout(timerRef.current);
      }
    };
  }, [router.isReady, router.query.session_id, attempts]);

  const statusLabel = (() => {
    switch (phase) {
      case 'success':
        return 'Aktivt medlemskap';
      case 'error':
        return 'Behöver din hjälp';
      case 'unauthorized':
        return 'Inloggning krävs';
      default:
        return 'Bearbetar betalningen';
    }
  })();

  const appLink = 'https://app.aveli.app';

  return (
    <>
      <Head>
        <title>Slutför betalning | Aveli</title>
        <meta
          name="description"
          content="Vi bekräftar din Stripe Checkout-betalning och aktiverar medlemskapet."
        />
      </Head>
      <main className={styles.page}>
        <section className={styles.card}>
          <span className={styles.badge}>Stripe Checkout</span>
          <h1 className={styles.title}>Betalning pågår</h1>
          <p className={styles.lead}>
            Vi verifierar din betalning och uppdaterar ditt medlemskap automatiskt. Detta kan ta upp
            till 30 sekunder.
          </p>

          <div className={styles.statusRow}>
            <span
              className={`${styles.pill} ${
                phase === 'success'
                  ? styles.success
                  : phase === 'error'
                    ? styles.error
                    : phase === 'unauthorized'
                      ? styles.warn
                      : styles.pending
              }`}
            >
              {statusLabel}
            </span>
            {sessionId ? (
              <span className={styles.sessionId}>
                session_id:
                <strong>{shortSessionId(sessionId)}</strong>
              </span>
            ) : null}
            {phase === 'pending' ? (
              <span className={styles.timer}>
                Återstår ~{Math.ceil(remainingMs / 1000)}s av kontrollen.
              </span>
            ) : null}
          </div>

          <p className={styles.lead}>{message}</p>
          {detail ? <p className={styles.muted}>{detail}</p> : null}

          {membershipStatus ? (
            <div className={styles.help}>
              <strong>Senast kända status:</strong> {membershipStatus}
            </div>
          ) : null}

          {phase === 'success' ? (
            <ul className={styles.list}>
              <li>Om du är i appen: stäng webbläsaren/WebView och fortsätt.</li>
              <li>Om du är i webben: gå till medlemskapssidan – du bör vara aktiv.</li>
            </ul>
          ) : null}

          {phase === 'error' || phase === 'unauthorized' ? (
            <div className={styles.help}>
              <ul className={styles.list}>
                <li>Öppna Aveli-appen och logga in, så hämtas medlemskapet igen.</li>
                <li>Om betalningen drogs men statusen står still: vänta 30–60 sek och försök igen.</li>
                <li>Behöver du hjälp? Kontakta support med ditt kvitto och session_id ovan.</li>
              </ul>
            </div>
          ) : null}

          <div className={styles.actions}>
            <Link href="/" className={`${styles.button} ${styles.secondary}`}>
              Till startsidan
            </Link>
            <a
              className={`${styles.button} ${styles.primary}`}
              href={appLink}
              rel="noreferrer"
              target="_blank"
            >
              Öppna appen
            </a>
            {(phase === 'error' || phase === 'pending') && (
              <button
                type="button"
                className={`${styles.button} ${styles.secondary}`}
                onClick={() => setAttempts((value) => value + 1)}
              >
                Försök igen
              </button>
            )}
          </div>
        </section>
      </main>
    </>
  );
}
