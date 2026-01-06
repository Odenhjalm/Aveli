import Head from 'next/head';
import Link from 'next/link';
import styles from '../../styles/CheckoutStatus.module.css';

export default function CheckoutCancel() {
  const appLink = 'https://app.aveli.app';

  return (
    <>
      <Head>
        <title>Betalning avbruten | Aveli</title>
        <meta
          name="description"
          content="Stripe Checkout avbröts. Ingen betalning drogs; du kan starta om från Aveli-appen."
        />
      </Head>
      <main className={styles.page}>
        <section className={styles.card}>
          <span className={styles.badge}>Stripe Checkout</span>
          <h1 className={styles.title}>Betalning avbruten</h1>
          <p className={styles.lead}>
            Ingen betalning drogs. Du kan gå tillbaka till appen och starta om checkout när du vill.
          </p>
          <div className={styles.help}>
            <ul className={styles.list}>
              <li>Öppna appen igen om du vill slutföra medlemskapet.</li>
              <li>Kontakta support om du råkade avsluta fönstret efter att ha betalat.</li>
            </ul>
          </div>
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
          </div>
        </section>
      </main>
    </>
  );
}
