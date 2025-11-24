import Head from 'next/head';
import Link from 'next/link';
import styles from '../styles/Legal.module.css';

export default function Terms() {
  return (
    <>
      <Head>
        <title>Användarvillkor – Aveli</title>
        <meta name="robots" content="noindex" />
      </Head>
      <main className={styles.main}>
        <nav className={styles.breadcrumb}>
          <Link href="/">Tillbaka</Link>
          <span>/</span>
          <span>Användarvillkor</span>
        </nav>
        <h1>Användarvillkor</h1>
        <p>
          Genom att använda Aveli accepterar du att endast publicera innehåll du
          själv äger rättigheterna till och att respektera community-guidelines.
        </p>
        <h2>Abonnemang och betalningar</h2>
        <p>
          Köp hanteras via Stripe. Avbokning kan göras när som helst och gäller
          inför nästa period. Återbetalningar hanteras enligt svensk lag.
        </p>
        <h2>Ansvarsbegränsning</h2>
        <p>
          Aveli levereras &quot;som den är&quot; utan garantier. Vi ansvarar inte för
          indirekta skador eller förluster.
        </p>
        <h2>Ändringar</h2>
        <p>
          Villkoren kan uppdateras vid större produktändringar. Fortsatt användning
          efter uppdatering innebär att du accepterar de nya villkoren.
        </p>
      </main>
    </>
  );
}
