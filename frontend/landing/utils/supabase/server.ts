import { createServerClient, type CookieOptions } from '@supabase/ssr';
import type { GetServerSidePropsContext, NextApiRequest, NextApiResponse } from 'next';

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabaseKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_DEFAULT_KEY;

type CookieToSet = {
  name: string;
  value: string;
  options?: CookieOptions;
};

type ServerContext = Pick<GetServerSidePropsContext, 'req' | 'res'> | {
  req: Pick<NextApiRequest, 'cookies'>;
  res: Pick<NextApiResponse, 'getHeader' | 'setHeader'>;
};

const serializeCookie = (
  name: string,
  value: string,
  options: CookieOptions = {}
) => {
  const parts = [`${name}=${encodeURIComponent(value)}`];

  if (typeof options.maxAge === 'number') {
    parts.push(`Max-Age=${Math.floor(options.maxAge)}`);
  }

  if (options.domain) {
    parts.push(`Domain=${options.domain}`);
  }

  parts.push(`Path=${options.path ?? '/'}`);

  if (options.expires) {
    parts.push(`Expires=${options.expires.toUTCString()}`);
  }

  if (options.httpOnly) {
    parts.push('HttpOnly');
  }

  if (options.sameSite) {
    const sameSite =
      typeof options.sameSite === 'string' ? options.sameSite : 'Lax';
    parts.push(`SameSite=${sameSite}`);
  }

  if (options.secure) {
    parts.push('Secure');
  }

  return parts.join('; ');
};

const appendCookies = (
  res: Pick<NextApiResponse, 'getHeader' | 'setHeader'>,
  cookiesToSet: CookieToSet[]
) => {
  const existing = res.getHeader('Set-Cookie');
  const currentCookies = Array.isArray(existing)
    ? existing
    : typeof existing === 'string'
      ? [existing]
      : [];

  const nextCookies = cookiesToSet.map(({ name, value, options }) =>
    serializeCookie(name, value, options)
  );

  res.setHeader('Set-Cookie', [...currentCookies, ...nextCookies]);
};

export const createClient = (context: ServerContext) =>
  createServerClient(supabaseUrl!, supabaseKey!, {
    cookies: {
      getAll() {
        return Object.entries(context.req.cookies ?? {}).map(([name, value]) => ({
          name,
          value: value ?? '',
        }));
      },
      setAll(cookiesToSet) {
        appendCookies(context.res, cookiesToSet);
      },
    },
  });
