import Head from 'next/head';
import Link from 'next/link';
import styles from '../styles/Legal.module.css';

export default function Gdpr() {
  return (
    <>
      <Head>
        <title>GDPR – Aveli</title>
        <meta name="robots" content="noindex" />
      </Head>
      <main className={styles.main}>
        <nav className={styles.breadcrumb}>
          <Link href="/">Tillbaka</Link>
          <span>/</span>
          <span>GDPR</span>
        </nav>
        <h1>GDPR</h1>
        <p>
          Aveli lagrar uppgifter inom EU och följer GDPR. Vi använder datan för
          att leverera utbildningsinnehåll, support och fakturering.
        </p>
        <h2>Dina rättigheter</h2>
        <p>
          Du har rätt att få tillgång till, korrigera eller radera dina uppgifter.
          Kontakta support@soulwisdom.dev för att utöva dina rättigheter.
        </p>
        <h2>Dataportabilitet</h2>
        <p>
          Exportera dina kurser och betalningshistorik via vår support. Vid behov
          kan vi tillhandahålla en Supabase-export för egen drift.
        </p>
        <h2>Personuppgiftsbiträden</h2>
        <p>
          Stripe och LiveKit agerar som personuppgiftsbiträden. Personuppgiftsavtal
          finns på plats och uppdateras löpande.
        </p>
      </main>
    </>
  );
}
