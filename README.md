# Metabase MySQL RLS Demo

Row-level security in **Metabase Enterprise** via MySQL 8 connection impersonation. Three users, same dashboard, different rows.

| User | Email | Is | Sees |
| --- | --- | --- | --- |
| Bruce Wayne | bruce@example.com | part of Analytics team | Everything |
| Thor Odinson | thor@example.com | part of East coast sales team | customers in some east coast states |
| Frodo Baggins | frodo@example.com | part of West coast sales team | customers in some west coast states |

All passwords: `metabot1`

---

## Prerequisites

- Docker Desktop
- Metabase Enterprise license token
- `bash`, `curl`, `jq` (Git Bash or WSL on Windows)

## Quick start

```bash
cp .env.example .env   # gitignored — set MB_PREMIUM_EMBEDDING_TOKEN inside
make start
```

Open `http://localhost:3300` when the terminal prints the summary.
First start takes a few minutes — it sets up the DB roles and policy, Metabase groups and permissions, and seeds the demo dashboard.

---

## How it works

The design mirrors PostgreSQL row-level security: in Postgres one could set up RLS policies on the `PEOPLE` table to define which rows each database role can see. To achieve the same in MySQL:

- each human gets a **personal DB role** (`h_role_bruce`, `h_role_thor`, `h_role_frodo`) — personal roles carry no data access on their own, they are an identity
- access is defined on **functional roles** (`f_role_analytics_team`, `f_role_sales_east_coast`, `f_role_sales_west_coast`); each functional role has rows in `rls_policy` declaring which column values it can see (e.g. 25 specific US state codes, or `*` for all)
- a human can belong to one or more functional roles via `rls_role_members`
- to secure `PEOPLE`, instead of a Postgres RLS policy we create `secure_people` — a `SECURITY DEFINER` view that filters `PEOPLE` to the states each functional role is allowed to see, by reading the querying user's active role and joining it to the RLS metadata tables above

> **Note:** No role in the database should have direct access to the raw `PEOPLE` table — everyone must query through `secure_people`.

On the Metabase side, [connection impersonation](https://www.metabase.com/docs/latest/permissions/impersonation) is used — each user has a `db_role` login attribute set to their personal DB role name. Each org group (Analytics Team, Sales East/West) is configured for connection impersonation on that attribute — so when a user runs any query, Metabase issues `SET ROLE <their db_role>` before it hits the database.

The enforcement lives entirely in the database. Even if a user opens the native SQL editor, they cannot query `PEOPLE` directly — they must go through `secure_people`, which filters to their allowed states.

**Minimizing migration impact on existing reports:** The one difference from Postgres RLS is that users must reference `secure_people` instead of `PEOPLE`. If you're adopting this on an existing system and want zero query changes, rename the raw table (`RENAME TABLE PEOPLE TO PEOPLE_raw`) and create the security view under the original name (`CREATE VIEW PEOPLE AS ...`). Existing queries continue to work unchanged; only `metabase_admin` is granted access to `PEOPLE_raw`. An alternative is a shadow schema (`sample_secure`) containing same-named views — unqualified queries still work, but any schema-qualified references (`sample.PEOPLE`) would need to be updated — so weigh those options to decide the easiest migration path.

---

## Admin Credentials

| | URL / host | User | Password |
|--|-----------|------|----------|
| Metabase | http://localhost:3300 | admin@example.com | metabot1 |
| MySQL | localhost:3366 db=`sample` | metabase | metasample123 |

## Lifecycle

```bash
make stop    # pause, data preserved
make reset   # wipe everything, start fresh
```
