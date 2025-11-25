import styles from './StoreButtons.module.css';

export function StoreButtons() {
  return (
    <div className={styles.wrapper}>
      <a
        href="https://play.google.com/store"
        aria-label="Öppna Google Play"
        className={`${styles.button} ${styles.play}`}
      >
        <span className={styles.heading}>Ladda ner på</span>
        <span className={styles.store}>Google Play</span>
      </a>
      <a
        href="https://apps.apple.com"
        aria-label="Öppna App Store"
        className={`${styles.button} ${styles.appStore}`}
      >
        <span className={styles.heading}>Hämta i</span>
        <span className={styles.store}>App Store</span>
      </a>
    </div>
  );
}
