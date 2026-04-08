============ 3 passed, 3 skipped, 46 warnings in 2.33s ==============
(.venv) oden@oden-Vector-16-HX-AI-A2XWHG:~/Wisdom/backend$ cd ~/Wisdom
(.venv) oden@oden-Vector-16-HX-AI-A2XWHG:~/Wisdom$ bash scripts/setup_local_backend.sh
==> Running database/bootstrap.sql
BEGIN
psql:database/bootstrap.sql:10: NOTICE:  extension "pgcrypto" already exists, skipping
CREATE EXTENSION
psql:database/bootstrap.sql:11: NOTICE:  extension "uuid-ossp" already exists, skipping
CREATE EXTENSION
DO
psql:database/bootstrap.sql:32: NOTICE:  schema "app" already exists, skipping
CREATE SCHEMA
psql:database/bootstrap.sql:34: NOTICE:  schema "auth" already exists, skipping
CREATE SCHEMA
psql:database/bootstrap.sql:74: NOTICE:  relation "users" already exists, skipping
CREATE TABLE
psql:database/bootstrap.sql:76: NOTICE:  relation "users_email_idx" already exists, skipping
CREATE INDEX
psql:database/bootstrap.sql:88: NOTICE:  relation "identities" already exists, skipping
CREATE TABLE
psql:database/bootstrap.sql:91: NOTICE:  relation "identities_provider_unique" already exists, skipping
CREATE INDEX
psql:database/bootstrap.sql:92: NOTICE:  relation "identities_user_idx" already exists, skipping
CREATE INDEX
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
psql:database/bootstrap.sql:169: NOTICE:  schema "storage" already exists, skipping
CREATE SCHEMA
psql:database/bootstrap.sql:181: NOTICE:  relation "buckets" already exists, skipping
CREATE TABLE
psql:database/bootstrap.sql:197: NOTICE:  relation "objects" already exists, skipping
CREATE TABLE
ALTER TABLE
COMMIT
==> Running database/schema.sql
BEGIN
psql:database/schema.sql:9: NOTICE:  schema "app" already exists, skipping
CREATE SCHEMA
psql:database/schema.sql:11: NOTICE:  extension "uuid-ossp" already exists, skipping
CREATE EXTENSION
psql:database/schema.sql:12: NOTICE:  extension "pgcrypto" already exists, skipping
CREATE EXTENSION
DO
DO
DO
DO
DO
psql:database/schema.sql:78: NOTICE:  relation "profiles" already exists, skipping
CREATE TABLE
psql:database/schema.sql:92: NOTICE:  relation "courses" already exists, skipping
CREATE TABLE
psql:database/schema.sql:101: NOTICE:  relation "modules" already exists, skipping
CREATE TABLE
psql:database/schema.sql:102: NOTICE:  relation "idx_modules_course" already exists, skipping
CREATE INDEX
psql:database/schema.sql:113: NOTICE:  relation "lessons" already exists, skipping
CREATE TABLE
psql:database/schema.sql:114: NOTICE:  relation "idx_lessons_module" already exists, skipping
CREATE INDEX
psql:database/schema.sql:125: NOTICE:  relation "lesson_media" already exists, skipping
CREATE TABLE
psql:database/schema.sql:126: NOTICE:  relation "idx_media_lesson" already exists, skipping
CREATE INDEX
psql:database/schema.sql:135: NOTICE:  relation "enrollments" already exists, skipping
CREATE TABLE
psql:database/schema.sql:136: NOTICE:  relation "idx_enroll_user" already exists, skipping
CREATE INDEX
psql:database/schema.sql:137: NOTICE:  relation "idx_enroll_course" already exists, skipping
CREATE INDEX
psql:database/schema.sql:145: NOTICE:  relation "memberships" already exists, skipping
CREATE TABLE
psql:database/schema.sql:159: NOTICE:  relation "orders" already exists, skipping
CREATE TABLE
psql:database/schema.sql:160: NOTICE:  relation "idx_orders_user" already exists, skipping
CREATE INDEX
psql:database/schema.sql:161: NOTICE:  relation "idx_orders_status" already exists, skipping
CREATE INDEX
CREATE TABLE
CREATE TABLE
CREATE INDEX
CREATE INDEX
CREATE INDEX
psql:database/schema.sql:197: NOTICE:  relation "purchases" already exists, skipping
CREATE TABLE
psql:database/schema.sql:198: NOTICE:  relation "idx_purchases_user" already exists, skipping
CREATE INDEX
psql:database/schema.sql:199: NOTICE:  relation "idx_purchases_course" already exists, skipping
CREATE INDEX
psql:database/schema.sql:200: NOTICE:  relation "idx_purchases_email" already exists, skipping
CREATE INDEX
psql:database/schema.sql:201: NOTICE:  relation "idx_purchases_order" already exists, skipping
CREATE INDEX
psql:database/schema.sql:211: NOTICE:  relation "guest_claim_tokens" already exists, skipping
CREATE TABLE
psql:database/schema.sql:212: NOTICE:  relation "idx_guest_claim_email" already exists, skipping
CREATE INDEX
psql:database/schema.sql:213: NOTICE:  relation "idx_guest_claim_purchase" already exists, skipping
CREATE INDEX
psql:database/schema.sql:220: NOTICE:  relation "app_config" already exists, skipping
CREATE TABLE
INSERT 0 0
psql:database/schema.sql:235: NOTICE:  relation "events" already exists, skipping
CREATE TABLE
psql:database/schema.sql:247: NOTICE:  relation "services" already exists, skipping
CREATE TABLE
DO
psql:database/schema.sql:262: NOTICE:  column "active" of relation "services" already exists, skipping
ALTER TABLE
psql:database/schema.sql:263: NOTICE:  relation "idx_services_provider" already exists, skipping
CREATE INDEX
psql:database/schema.sql:274: NOTICE:  relation "teacher_requests" already exists, skipping
CREATE TABLE
psql:database/schema.sql:282: NOTICE:  relation "teacher_directory" already exists, skipping
CREATE TABLE
psql:database/schema.sql:290: NOTICE:  relation "teacher_permissions" already exists, skipping
CREATE TABLE
CREATE TABLE
CREATE TABLE
CREATE INDEX
CREATE TABLE
CREATE INDEX
CREATE INDEX
CREATE TABLE
CREATE INDEX
CREATE TABLE
CREATE TABLE
CREATE INDEX
CREATE TABLE
CREATE INDEX
CREATE INDEX
CREATE TABLE
CREATE INDEX
CREATE INDEX
psql:database/schema.sql:382: NOTICE:  relation "teacher_slots" already exists, skipping
CREATE TABLE
psql:database/schema.sql:383: NOTICE:  relation "idx_slots_teacher" already exists, skipping
CREATE INDEX
psql:database/schema.sql:393: NOTICE:  relation "bookings" already exists, skipping
CREATE TABLE
psql:database/schema.sql:401: NOTICE:  relation "pro_requirements" already exists, skipping
CREATE TABLE
INSERT 0 3
psql:database/schema.sql:423: NOTICE:  relation "pro_progress" already exists, skipping
CREATE TABLE
psql:database/schema.sql:435: NOTICE:  relation "certificates" already exists, skipping
CREATE TABLE
ALTER TABLE
CREATE INDEX
psql:database/schema.sql:446: NOTICE:  relation "teacher_approvals" already exists, skipping
CREATE TABLE
psql:database/schema.sql:458: NOTICE:  relation "tarot_requests" already exists, skipping
CREATE TABLE
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
DROP FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
ALTER TABLE
ALTER TABLE
ALTER TABLE
ALTER TABLE
ALTER TABLE
ALTER TABLE
ALTER TABLE
ALTER TABLE
ALTER TABLE
ALTER TABLE
ALTER TABLE
ALTER TABLE
ALTER TABLE
ALTER TABLE
ALTER TABLE
ALTER TABLE
ALTER TABLE
ALTER TABLE
ALTER TABLE
ALTER TABLE
ALTER TABLE
ALTER TABLE
ALTER TABLE
ALTER TABLE
ALTER TABLE
ALTER TABLE
ALTER TABLE
ALTER TABLE
DROP POLICY
CREATE POLICY
DROP POLICY
CREATE POLICY
DROP POLICY
CREATE POLICY
DROP POLICY
CREATE POLICY
DROP POLICY
CREATE POLICY
DROP POLICY
CREATE POLICY
DROP POLICY
CREATE POLICY
DROP POLICY
CREATE POLICY
DROP POLICY
CREATE POLICY
DROP POLICY
CREATE POLICY
DROP POLICY
CREATE POLICY
DROP POLICY
CREATE POLICY
DROP POLICY
CREATE POLICY
DROP POLICY
CREATE POLICY
DROP POLICY
CREATE POLICY
DROP POLICY
CREATE POLICY
DROP POLICY
CREATE POLICY
DROP POLICY
CREATE POLICY
DROP POLICY
CREATE POLICY
DROP POLICY
CREATE POLICY
DROP POLICY
CREATE POLICY
DROP POLICY
CREATE POLICY
REVOKE
DROP POLICY
CREATE POLICY
DROP POLICY
CREATE POLICY
DROP POLICY
CREATE POLICY
DROP POLICY
CREATE POLICY
DROP POLICY
CREATE POLICY
DROP POLICY
CREATE POLICY
DROP POLICY
psql:database/schema.sql:959: ERROR:  column "is_active" does not exist
HINT:  Perhaps you meant to reference the column "serv