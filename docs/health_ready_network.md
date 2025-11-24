# Health, Readiness & Network

## FastAPI endpoints
- `GET /healthz` → snabb liveness (returnerar `{ "status": "ok" }`).
- `GET /readyz` → kör `SELECT 1` mot Postgres via `psycopg_pool`; svarar `503` om poolen inte är öppen.
- `GZipMiddleware` komprimerar svar >512 byte så statiska/kursdata levereras snabbare till mobila klienter.

## Proxy (nginx)
- Se `docs/nginx_http2_quic.conf` för ett exempel som aktiverar `listen ... http2` + `listen ... quic` samt H3 Alt-Svc header.
- `map $host $cors_allow_origin` begränsar CORS till respektive miljö (prod/staging/dev) istället för en bred `*`-lista.
- Proxy:n skickar vidare `X-Request-ID` så FastAPI:s middleware och loggar kan kedja samman HTTP/2, HTTP/3 och backend-spårning.

## Testinstruktioner
1. `curl -sf https://api.aveli.app/healthz` → ska returnera `{"status":"ok"}`.
2. Simulera databasfel (stoppa Postgres) och verifiera att `/readyz` ger `503`.
3. Kontrollera GZip: `curl -H 'Accept-Encoding: gzip' -I https://api.aveli.app/api/courses` och se `Content-Encoding: gzip`.
4. Kör `nghttp -n 1 https://api.aveli.app/healthz` för att bekräfta HTTP/2; använd `curl --http3` för QUIC.
