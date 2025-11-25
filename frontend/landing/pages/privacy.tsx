import Head from 'next/head';
import Link from 'next/link';
import styles from '../styles/Legal.module.css';

export default function Privacy() {
  return (
    <>
      <Head>
        <title>Integritetspolicy – Aveli</title>
        <meta name="robots" content="noindex" />
      </Head>
      <main className={styles.main}>
        <nav className={styles.breadcrumb}>
          <Link href="/">Tillbaka</Link>
          <span>/</span>
          <span>Integritetspolicy</span>
        </nav>
        <h1>Integritetspolicy</h1>
        <p>
          Vi behandlar personuppgifter för att kunna leverera kurser, community
          och live-seminarier. All data lagras i vår lokala Postgres-instans och
          kan exporteras till Supabase för fortsatt drift.
        </p>
        <h2>Vilka uppgifter sparas?</h2>
        <p>
          Kontoinformation (e-post, visningsnamn), kursprogression, beställningar
          och transaktioner via Stripe. Vid Liveseminarier skapas tillfälliga
          tokens hos LiveKit.
        </p>
        <h2>Hur länge sparas uppgifter?</h2>
        <p>
          Uppgifter sparas så länge kontot är aktivt eller enligt gällande lag.
          Du kan begära export eller radering genom att kontakta
          support@soulwisdom.dev.
        </p>
        <h2>Delning med tredjepart</h2>
        <p>
          Stripe används för betalningar och LiveKit för realtidsvideo. Dessa
          leverantörer får endast de uppgifter som krävs för att tillhandahålla
          tjänsten.
        </p>
      </main>
    </>
  );
}
