# Claude Code context — Metabase MySQL RLS Demo

MySQL 8 row-level security via Metabase Enterprise connection impersonation. One `make start` → running demo.

---

## Demo scenario

| Metabase user | DB personal role | Team role | Visible states |
|---|---|---|---|
| bruce@example.com | h_role_bruce | f_role_analytics_team | All 50 (wildcard `*`) |
| thor@example.com | h_role_thor | f_role_sales_east_coast | 25 east states |
| frodo@example.com | h_role_frodo | f_role_sales_west_coast | 25 west states |

East (Thor): AL CT DE FL GA IL IN KY MA MD ME MI MS NC NH NJ NY OH PA RI SC TN VA VT WV  
West (Frodo): AK AR AZ CA CO HI IA ID KS LA MN MO MT ND NE NM NV OK OR SD TX UT WA WI WY

---

## Architecture — the important WHYs

**Only PEOPLE is secured — mimics Postgres RLS**  
`ORDERS`, `PRODUCTS`, `REVIEWS` have no row restriction (functional roles get raw SELECT — same as Postgres with no policy on those tables). `PEOPLE` is blocked; the only way to read customer/territory data is through `secure_people`. Any query that needs state data must JOIN through `secure_people`; the territory filter materializes naturally at that join boundary.

**SECURITY DEFINER view, not SECURITY INVOKER**  
`secure_people` is SECURITY DEFINER so root reads the underlying PEOPLE table, while `CURRENT_ROLE()` still reflects the caller's active session role. Do not change this.

**System roles bypass policy via `rls_superusers`**  
`metabase_admin` is in `rls_superusers`, not in `rls_role_members`/`rls_policy`. The view's WHERE clause checks `EXISTS (SELECT 1 FROM rls_superusers WHERE mysql_role = <current role>)` first — if true, all rows are returned. This is an inline EXISTS, not a stored function: `SQL SECURITY DEFINER` functions return the definer's `CURRENT_ROLE()` (NONE), not the caller's. The view itself does not have this problem.  
To add a new service account: insert one row into `rls_superusers` — no view or policy changes needed.

**Two-table policy model**  
- `rls_policy`: team role → allowed filter values. Rarely changes.  
- `rls_role_members`: personal role → team role(s). One row per membership.  
Adding a new person requires no changes to `rls_policy` or the view. Do not collapse into one table.

**Wildcard `*` in rls_policy**  
Analytics team has one row with `filter_value = '*'`. The EXISTS clause checks `filter_value = '*' OR filter_value = pe.state`.

**EXISTS not JOIN in the view**  
Prevents row fanout if someone belongs to two team roles. EXISTS returns each person at most once.

**Metabase impersonation is user-attribute-based**  
Impersonation is configured directly on each org group (Analytics Team, Sales East/West) with `attribute: db_role`. Metabase reads each user's `db_role` attribute and issues `SET ROLE <value>`. There is no separate RLS Users group — org groups handle both collection access and DB impersonation. If a user belongs to multiple impersonated groups, Metabase uses the `db_role` attribute consistently across all of them.

**Personal roles, not direct team roles**  
`CURRENT_ROLE()` returns only the directly SET role, not inherited sub-roles. Personal roles give each user a stable DB identity; team memberships can change via `rls_role_members` without touching MySQL or Metabase config.

---

## File structure

```
.env.example          # copy to .env; set MB_PREMIUM_EMBEDDING_TOKEN
.mysql-seeded         # created by start.sh after RLS SQL runs; skip re-seeding on restart
docker-compose.yml    # metabase, mysql (qa-databases:mysql-sample-8), app-db (postgres:18-alpine)
Makefile              # start / stop / reset (reset also deletes .mysql-seeded)
scripts/start.sh      # DBs → RLS SQL → Metabase → seed → summary
seed/config.yml       # Metabase first-boot: users, API key, DB connection
seed/mysql-rls.sql    # roles, rls_superusers, rls_policy, rls_role_members, secure_people view, grants
seed/seed-metabase.sh # groups, user attributes, impersonation, cards, dashboard via Metabase API
```

**MySQL data source**: `metabase/qa-databases:mysql-sample-8` loads sample data via `/docker-entrypoint-initdb.d/` on first start (not pre-baked). The healthcheck queries `REVIEWS` to confirm data is ready before RLS SQL runs.  
Tables are **UPPERCASE** (`ORDERS`, `PRODUCTS`, `PEOPLE`, `REVIEWS`) — `lower_case_table_names=0`.  
Credentials: user=metabase, password=metasample123, db=sample, root password=metasample123.

**config.yml**: read on first Metabase boot only. Changes require `make reset`.

**mysql-rls.sql**: idempotent (`CREATE ROLE IF NOT EXISTS`, `INSERT IGNORE`, `CREATE OR REPLACE VIEW`, `REVOKE IF EXISTS`). Skipped on restart if `.mysql-seeded` exists.

**seed-metabase.sh**: idempotent; checks existence before creating. Uses `PUT /api/permissions/graph` with an `impersonations` array to configure impersonation (not `POST /api/ee/impersonation` — that 404s in 1.62.x).

---

## The three demo cards

1. **Active Role** — `SELECT CURRENT_ROLE()`. Shows which personal role Metabase activated.
2. **My Team Memberships** — queries `rls_superusers` (returns `superuser`) then `rls_role_members` (returns team roles) via UNION ALL. Shows the full policy chain for any role type.
3. **Orders by State** — `SELECT p.state, COUNT(*), SUM(o.total) FROM ORDERS o JOIN secure_people p ON p.id = o.user_id GROUP BY p.state`. US region map viz. Bruce = 50 states, Thor = 25 east, Frodo = 25 west.

---

## How to add a new sales rep (e.g. Gandalf)

```sql
CREATE ROLE IF NOT EXISTS 'h_role_gandalf';
GRANT 'f_role_sales_west_coast' TO 'h_role_gandalf';
GRANT 'h_role_gandalf' TO 'metabase'@'%';
INSERT IGNORE INTO rls_role_members VALUES ('h_role_gandalf', 'f_role_sales_west_coast');
FLUSH PRIVILEGES;
```
In Metabase: create gandalf@example.com, set `db_role = "h_role_gandalf"`, add to the appropriate org group (e.g. Sales West Coast).

---

## Known pitfalls

- **Admin queries raw tables directly** — `metabase_admin` is in `rls_superusers`, so the admin bypasses impersonation and queries ORDERS/PRODUCTS/PEOPLE/REVIEWS directly. Human roles cannot query PEOPLE at all (access denied); they must go through `secure_people`.
- **mysql-rls.sql is not a transaction** — DDL auto-commits. Mid-script failure leaves partial state until `make reset`.
- **config.yml changes ignored** — only read on first Metabase boot. Requires `make reset`.
- **`make stop` keeps data; `make reset` wipes it** — seed-metabase.sh is safe to re-run (existence checks).

---

## Environment variables (.env)

| Variable | Default | Purpose |
|---|---|---|
| MB_PREMIUM_EMBEDDING_TOKEN | (required) | Enterprise license — needed for connection impersonation |
| MB_IMAGE_TAG | 1.62.2.x | Metabase Enterprise image tag (`x` floats on latest patch) |
| METABASE_PORT | 3300 | Host port for Metabase |
