import * as Sentry from '@sentry/nextjs';

Sentry.init({
  dsn: process.env.NEXT_PUBLIC_SENTRY_DSN || process.env.SENTRY_DSN || undefined,
  tracesSampleRate: 0.2,
  enabled:
    Boolean(process.env.NEXT_PUBLIC_SENTRY_DSN) ||
    Boolean(process.env.SENTRY_DSN),
});
