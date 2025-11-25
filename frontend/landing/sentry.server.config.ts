import * as Sentry from '@sentry/nextjs';

Sentry.init({
  dsn: process.env.SENTRY_DSN || process.env.NEXT_PUBLIC_SENTRY_DSN || undefined,
  tracesSampleRate: 0.2,
  enabled:
    Boolean(process.env.SENTRY_DSN) ||
    Boolean(process.env.NEXT_PUBLIC_SENTRY_DSN),
});
