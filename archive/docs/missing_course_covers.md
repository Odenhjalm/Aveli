# Missing Course Covers Backlog

Updated: 2025-10-13  
Latest revision: 2025-10-13 – QA backlog cleanup complete

This file tracks courses that surface without a `cover_url`. The companion machine-readable list lives in `docs/missing_course_covers.json`.

## Summary (October 2025)
- QA placeholder courses (`course-*` / `premium-*`) were removed from the database on 2025‑10‑13 (72 rows deleted).
- Status recap:
-  **Att tänka själv** (`att-tänka-själv-4yfs-hbuo58am2l`) – cover fixed on 2025‑10‑13 (`/studio/media/a461129c-…`).
-  **Vem tänker och vem hör tankar ?** (`vem-tänker-och-vem-hör-tankar-aevu-hbuo6wmmc1`) – omslag uppladdat via Studio (`/studio/media/b1be5776-b4bb-496a-9d7c-2465b8e48d85`).

## Cleanup SQL (run against non-production environments when QA seeds reappear)

```sql
delete from app.courses
where slug like 'course-%'
   or slug like 'premium-%';
```

Foreign keys cascade to modules/lessons/media, so no further action is needed after running the statement.

## How to log new gaps

1. When a real course lacks a cover, add an entry to `docs/missing_course_covers.json` with:
   - `owner`: responsible designer/teacher email.
   - `status`: e.g. `needs_cover`, `in_progress`, `done`.
   - `notes`: context and due date.
2. Mirror the key details in this markdown file so audits have narrative context.
3. Once the cover is live, remove the JSON entry and update this file with the resolution.

With the backlog empty, any future entries will signal actual work that needs follow-up.
