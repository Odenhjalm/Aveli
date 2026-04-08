# RLS Matrix

## app.courses
| Roll | SELECT | INSERT | UPDATE | DELETE |
| --- | --- | --- | --- | --- |
| Public (anon) | Endast `status = 'published'` | – | – | – |
| Authenticated | Alla rader, men bara läsning | – | – | – |
| Teacher | Se allt, `INSERT` egna kurser (`created_by = auth.uid()`), uppdatera/ta bort endast där `created_by = auth.uid()` | Ja | Ja (egna) | Ja (egna) |
| Admin | Full `SELECT/INSERT/UPDATE/DELETE` | Ja | Ja | Ja |

## app.teacher_profiles
| Roll | SELECT | INSERT | UPDATE | DELETE |
| --- | --- | --- | --- | --- |
| Public | Endast publicerade/approved lärare | – | – | – |
| Authenticated | Samma som public + se egna draft-profiler | – | – | – |
| Teacher | Läsa allt, `INSERT`/`UPDATE` sin egen profil (`user_id = auth.uid()`), ej `DELETE` | Ja | Ja (egen) | – |
| Admin | Full kontroll | Ja | Ja | Ja |

## app.seminars
| Roll | SELECT | INSERT | UPDATE | DELETE |
| --- | --- | --- | --- | --- |
| Public/Anon | Publika seminarier (`status in ('scheduled','live','ended')`) | – | – | – |
| Authenticated | Samma som public + egna seminarier/registreringar via `app.can_access_seminar(id)` | Endast om `host_id = auth.uid()` | Endast värd (`app.is_seminar_host(id)`) | Endast värd |
| Service role | Full åtkomst via `auth.role() = 'service_role'` bypass | Ja | Ja | Ja |

Policies använder de hårdnade helper-funktionerna:
- `seminars_public_read` – `USING status ... OR app.can_access_seminar(id)`
- `seminars_host_*` – styr `INSERT/UPDATE/DELETE` med `app.is_seminar_host(id)` och `host_id = auth.uid()`.

## app.seminar_attendees
| Roll | SELECT | INSERT | UPDATE | DELETE |
| --- | --- | --- | --- | --- |
| Authenticated | Får se rader där de själva deltar eller där de är värd (via `app.is_seminar_attendee` / `app.is_seminar_host`) | Lägg till sig själv eller, om värd, andra deltagare | Uppdatera status för sig själv eller värdens deltagare | Ta bort sin egen rad eller värden tar bort andra |
| Service role | Full åtkomst | Ja | Ja | Ja |

Policies:
- `seminar_attendees_read` – `USING app.is_seminar_attendee(seminar_id) OR app.is_seminar_host(seminar_id)`.
- `seminar_attendees_insert/update/delete` – kombinerar `auth.uid()` med helper-funktionerna så att bara värdar/service kan hantera andras rader.

## app.lesson_media
| Roll | SELECT | INSERT | UPDATE | DELETE |
| --- | --- | --- | --- | --- |
| Public | – | – | – | – |
| Authenticated | Får läsa poster kopplade till lektioner de äger eller köpt åtkomst till | – | – | – |
| Teacher | Läsa och skapa media knuten till lektioner de äger (via `lesson.owner_id = auth.uid()`), uppdatera/ta bort egna media-objekt | Ja (egna) | Ja (egna) | Ja (egna) | Ja (egna) |
| Admin | Full kontroll | Ja | Ja | Ja |

## storage.objects (`lesson_media`-bucket)
| Roll | SELECT | INSERT | UPDATE | DELETE |
| --- | --- | --- | --- | --- |
| Public | – | – | – | – |
| Authenticated | Läsning styrs via signerade URL:er – ingen direktåtkomst | – | – | – |
| Teacher | `INSERT`/`UPDATE`/`DELETE` begränsad till objekt där metadata `owner_id = auth.uid()` eller via signerad PUT | Ja (via signerad URL) | Ja (egna) | Ja (egna) | Ja (egna) |
| Admin | Full åtkomst med service role key | Ja | Ja | Ja | Ja |

## Lärarbehörigheter
- Lärare identifieras via `profiles.role_v2 = 'teacher'` eller `app.teacher_accounts`.
- De får skapa/redigera: kurser, moduler, lektioner, `lesson_media`, profil-media och Supabase-objekt där `owner_id = auth.uid()`.
- Alla andra operations (betalningar, community, adminsidor) kräver `is_admin = true`.

> Uppdatera tabellen när RLS-policys läggs till/ändras så att klienter kan besluta vilka knappar som ska visas per roll.
