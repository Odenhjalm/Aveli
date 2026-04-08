# Resumable WAV Upload Research (Supabase Storage) - 2026-01-23

Sources:
- Supabase Storage docs: Resumable uploads
- tus.io protocol: Resumable upload (v1.0)

Key findings (primary-source summary):

1) Endpoint + session lifecycle (Supabase)
- Endpoint: `POST /storage/v1/upload/resumable` creates a resumable upload session.
- The response includes a unique upload URL in the `Location` header.
- The upload URL is valid for 24 hours and can be used to resume the upload.
- Concurrent usage of the same upload URL from multiple clients yields `409 Conflict`.

2) Required headers + metadata (Supabase + tus)
- `Tus-Resumable: 1.0.0` is required for POST/HEAD/PATCH requests.
- POST requires `Upload-Length` and `Upload-Metadata` headers.
- Supabase metadata keys: `bucketName`, `objectName`, `contentType`, `cacheControl`, `metadata` (JSON string).
- For Supabase resumable uploads, `x-upsert` is supported and should match create/overwrite behavior.

3) Auth options (Supabase)
- Standard auth: `Authorization: Bearer <access_token>` for each request.
- Signed token auth: `x-signature` header using the token returned by `createSignedUploadUrl`.

4) Chunking + commit behavior (tus)
- `PATCH` requests use `Content-Type: application/offset+octet-stream`.
- The client sends `Upload-Offset` for each chunk.
- The server responds with updated `Upload-Offset`, representing persisted bytes.
- Use `HEAD` to fetch the current offset for resume.

5) Resume + retry semantics (tus)
- Resume requires a `HEAD` request to read `Upload-Offset`.
- `Upload-Expires` can be returned to signal session expiry.
- `409 Conflict` indicates offset mismatch; clients should re-sync via `HEAD`.
- `404`/`410` indicates expired or invalid session.

6) Supabase-specific constraints
- Supabase docs specify a 6 MB chunk size for resumable uploads.

Planned usage for the web client:
- Use the signed upload token (x-signature) derived from the existing signed upload URL.
- POST to `/storage/v1/upload/resumable` with Tus headers + metadata to create session.
- Persist session URL and resume metadata in localStorage for refresh recovery.
- Use HEAD + PATCH to resume and update progress using server `Upload-Offset` only.
