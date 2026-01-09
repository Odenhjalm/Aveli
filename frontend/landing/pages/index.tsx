import Head from 'next/head';
import Link from 'next/link';
import Image from 'next/image';
import { StoreButtons } from '../components/StoreButtons';
import styles from '../styles/Home.module.css';

export default function Home() {
  return (
    <>
      <Head>
        <title>Aveli</title>
        <meta
          name="description"
          content="Guided kurser, community och livesända ceremonier för själslig utveckling."
        />
      </Head>
      <main className={styles.layout}>
        <header className={styles.hero}>
          <div className={styles.badge}>Ny plattform</div>
          <h1>Aveli</h1>
          <p className={styles.lead}>
            Fördjupa din spirituella praktik med kurser, personliga tjänster och
            live-seminarier – byggda för lärare och sökare tillsammans.
          </p>
          <StoreButtons />
          <div className={styles.links}>
            <Link href="/login" className={styles.primaryLink}>
              Logga in
            </Link>
            <Link href="/privacy" className={styles.secondaryLink}>
              Integritetspolicy
            </Link>
          </div>
        </header>

        <section className={styles.showcase}>
          <article className={styles.card}>
            <Image
              src="/icons/icon-courses.svg"
              alt=""
              width={48}
              height={48}
            />
            <h2>Mina kurser</h2>
            <p>
              Progression, quiz och certifikat – hanteras lokalt och redo för
              Supabase-export.
            </p>
          </article>
          <article className={styles.card}>
            <Image
              src="/icons/icon-services.svg"
              alt=""
              width={48}
              height={48}
            />
            <h2>Tjänster & Stripe</h2>
            <p>
              Byggt på FastAPI + Postgres med färdiga endpoints för ordrar,
              checkout och webhookar.
            </p>
          </article>
          <article className={styles.card}>
            <Image src="/icons/icon-live.svg" alt="" width={48} height={48} />
            <h2>LiveKit</h2>
            <p>
              SFU-token service klar – koppla appen till LiveKit Cloud och
              skapa livesända ceremonier.
            </p>
          </article>
        </section>

        <footer className={styles.footer}>
          <nav>
            <Link href="/privacy">Privacy</Link>
            <Link href="/terms">Terms</Link>
            <Link href="/gdpr">GDPR</Link>
          </nav>
          <p>© {new Date().getFullYear()} Aveli. Alla rättigheter förbehålls.</p>
        </footer>
      </main>
    </>
  );
}
