# OAuth Auth Table Fix Report

## Before snapshot
```
Pager usage is off.
Output format is aligned.
Null display is "(NULL)".
Counts
 total_users 
-------------
         140
(1 row)

 aud_nulls | role_nulls | email_confirmed_nulls | email_nulls 
-----------+------------+-----------------------+-------------
       139 |        139 |                   139 |           0
(1 row)


aud NULL rows (id, email)
                  id                  |              email              
--------------------------------------+---------------------------------
 e4ec9b47-5d9d-4490-aa83-2c364b7b0141 | smoke_6acaa6@wisdom.dev
 1d6e8a92-2c3b-44fb-a5d6-82e977a21282 | billing_3521a936@example.com
 586b40e2-842c-4ae8-8f63-dcd7e3daf916 | billing_28ced4e2@example.com
 c635e150-818b-4d43-be20-182a1a402a16 | free_intro_e1913d67@example.com
 010faf6d-9d7c-42f0-8fee-781de75d352e | me_42f925b3@example.com
 9365d86f-89f1-4999-99c6-9b9d548fea3d | free_intro_ff8e0b8c@example.com
 8397fd86-7644-48ef-8597-c43c881607bf | billing_61620e11@example.com
 f8a27f62-3fa0-46ed-8766-da34c63282b8 | feed_f91c37@example.com
 550c5eda-47f5-4170-942f-ad4ee7d9f73a | billing_7dbbf274@example.com
 a8e2439e-3a35-46da-b1ef-5e30fc8b7f28 | mvp_3ab5e8@aveli.local
 fbfcc81c-4eda-4678-87ef-b9c42a220209 | teacher_c66449@wisdom.dev
 bb29d9c0-2109-4ed0-a690-0307939db93b | smoke_c73967@wisdom.dev
 c982dbb0-c9af-4a54-871b-12ea7e14e14a | billing_ecd7c4aa@example.com
 446ba079-3ac3-4ee3-9e31-b7ddb3b44510 | billing_cf719cd8@example.com
 cdf0c41c-54f3-4944-a2ed-6cf5730e6aa8 | free_intro_8adc2f2b@example.com
 5b31128b-d601-410b-b260-3f2e013f47ec | me_740dd52f@example.com
 8d611630-35b1-4d7b-9cb7-655d4ef92270 | free_intro_000277c2@example.com
 7d5c6764-40f3-4b93-9b35-67439697f5bb | billing_89f0f792@example.com
 db23b157-7b9c-4e5a-ba90-e2114d091332 | feed_17b6a9@example.com
 2e62bce7-abcd-4146-a2ca-01c96474f214 | billing_4c9867b9@example.com
(20 rows)


role NULL rows (id, email)
                  id                  |              email              
--------------------------------------+---------------------------------
 e4ec9b47-5d9d-4490-aa83-2c364b7b0141 | smoke_6acaa6@wisdom.dev
 1d6e8a92-2c3b-44fb-a5d6-82e977a21282 | billing_3521a936@example.com
 586b40e2-842c-4ae8-8f63-dcd7e3daf916 | billing_28ced4e2@example.com
 c635e150-818b-4d43-be20-182a1a402a16 | free_intro_e1913d67@example.com
 010faf6d-9d7c-42f0-8fee-781de75d352e | me_42f925b3@example.com
 9365d86f-89f1-4999-99c6-9b9d548fea3d | free_intro_ff8e0b8c@example.com
 8397fd86-7644-48ef-8597-c43c881607bf | billing_61620e11@example.com
 f8a27f62-3fa0-46ed-8766-da34c63282b8 | feed_f91c37@example.com
 550c5eda-47f5-4170-942f-ad4ee7d9f73a | billing_7dbbf274@example.com
 a8e2439e-3a35-46da-b1ef-5e30fc8b7f28 | mvp_3ab5e8@aveli.local
 fbfcc81c-4eda-4678-87ef-b9c42a220209 | teacher_c66449@wisdom.dev
 bb29d9c0-2109-4ed0-a690-0307939db93b | smoke_c73967@wisdom.dev
 c982dbb0-c9af-4a54-871b-12ea7e14e14a | billing_ecd7c4aa@example.com
 446ba079-3ac3-4ee3-9e31-b7ddb3b44510 | billing_cf719cd8@example.com
 cdf0c41c-54f3-4944-a2ed-6cf5730e6aa8 | free_intro_8adc2f2b@example.com
 5b31128b-d601-410b-b260-3f2e013f47ec | me_740dd52f@example.com
 8d611630-35b1-4d7b-9cb7-655d4ef92270 | free_intro_000277c2@example.com
 7d5c6764-40f3-4b93-9b35-67439697f5bb | billing_89f0f792@example.com
 db23b157-7b9c-4e5a-ba90-e2114d091332 | feed_17b6a9@example.com
 2e62bce7-abcd-4146-a2ca-01c96474f214 | billing_4c9867b9@example.com
(20 rows)


OAuth users (non-email identities)
                  id                  |         email         |      aud      |     role      |      email_confirmed_at       | provider_meta 
--------------------------------------+-----------------------+---------------+---------------+-------------------------------+---------------
 ba83aa88-0c1e-47e8-aaaa-8d3d791bd979 | odenhjalm@outlook.com | authenticated | authenticated | 2025-11-27 23:05:41.223189+00 | google
(1 row)


Email NULL + non-email created_via (raw_app_meta_data->>provider)
 id | email | raw_app_meta_data 
----+-------+-------------------
(0 rows)

```

## Changes applied
- Set aud='authenticated' for 139 rows with NULL aud
- Set role='authenticated' for 139 rows with NULL role
- Checked OAuth users missing confirmation (none matched)
- Normalized provider metadata where missing (none matched)
- Deleted zombie users with NULL email (none matched)

## After snapshot
```
Pager usage is off.
Output format is aligned.
Null display is "(NULL)".
Counts after fixes
 total_users 
-------------
         140
(1 row)

 aud_nulls | role_nulls | email_confirmed_nulls | email_nulls 
-----------+------------+-----------------------+-------------
         0 |          0 |                   139 |           0
(1 row)


aud NULL rows (should be 0)
 id | email 
----+-------
(0 rows)


role NULL rows (should be 0)
 id | email 
----+-------
(0 rows)


OAuth users (non-email identities)
                  id                  |         email         |      aud      |     role      |      email_confirmed_at       | provider_meta 
--------------------------------------+-----------------------+---------------+---------------+-------------------------------+---------------
 ba83aa88-0c1e-47e8-aaaa-8d3d791bd979 | odenhjalm@outlook.com | authenticated | authenticated | 2025-11-27 23:05:41.223189+00 | google
(1 row)

```
