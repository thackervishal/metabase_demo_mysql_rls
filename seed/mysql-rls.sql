-- MySQL 8 RLS setup. Run as root against the `sample` database.
--
-- Mimics PostgreSQL row-level security on the PEOPLE table:
--   ORDERS, PRODUCTS, REVIEWS — no row restriction (full access, like Postgres with no policy).
--   PEOPLE — access only through secure_people, which filters by allowed states.
--   Any query that needs territory data must JOIN through secure_people; the filter
--   materializes naturally at that join boundary, exactly as Postgres RLS would.
--
-- Human roles (h_role_*): one per person. Identity only — no data grants of their own.
-- Functional roles (f_role_*): define which filter values are allowed (via rls_policy).
-- System roles (metabase_admin): bypass policy entirely via rls_superusers.

-- ── Functional roles ──────────────────────────────────────────────────────────

CREATE ROLE IF NOT EXISTS 'f_role_analytics_team';
CREATE ROLE IF NOT EXISTS 'f_role_sales_east_coast';
CREATE ROLE IF NOT EXISTS 'f_role_sales_west_coast';

-- ── Human roles (one per person) ─────────────────────────────────────────────

CREATE ROLE IF NOT EXISTS 'h_role_bruce';   -- bruce@example.com  — Bruce Wayne
CREATE ROLE IF NOT EXISTS 'h_role_thor';    -- thor@example.com   — Thor Odinson
CREATE ROLE IF NOT EXISTS 'h_role_frodo';   -- frodo@example.com  — Frodo Baggins

-- ── System bypass table ───────────────────────────────────────────────────────
-- Roles listed here bypass all row-level policy and see every row in secure views.
-- To add a new system/service account: INSERT one row and grant the role to 'metabase'@'%'.

CREATE TABLE IF NOT EXISTS rls_superusers (
    mysql_role VARCHAR(200) NOT NULL,
    PRIMARY KEY (mysql_role)
);

INSERT IGNORE INTO rls_superusers VALUES ('metabase_admin');

-- ── Policy table: functional role → allowed filter values ─────────────────────
-- The filter is people.state — state lives on PEOPLE, so table_name = 'people'.
-- filter_value '*' means all rows (wildcard, used by analytics team).

CREATE TABLE IF NOT EXISTS rls_policy (
    mysql_role    VARCHAR(200) NOT NULL,
    table_name    VARCHAR(100) NOT NULL,
    filter_column VARCHAR(100) NOT NULL,
    filter_value  VARCHAR(200) NOT NULL,
    PRIMARY KEY (mysql_role, table_name, filter_column, filter_value)
);

INSERT IGNORE INTO rls_policy VALUES
    -- Analytics Team: all states
    ('f_role_analytics_team',   'people', 'state', '*'),

    -- Sales East Coast (Thor): AL CT DE FL GA IL IN KY MA MD ME MI MS NC NH NJ NY OH PA RI SC TN VA VT WV
    ('f_role_sales_east_coast', 'people', 'state', 'AL'),
    ('f_role_sales_east_coast', 'people', 'state', 'CT'),
    ('f_role_sales_east_coast', 'people', 'state', 'DE'),
    ('f_role_sales_east_coast', 'people', 'state', 'FL'),
    ('f_role_sales_east_coast', 'people', 'state', 'GA'),
    ('f_role_sales_east_coast', 'people', 'state', 'IL'),
    ('f_role_sales_east_coast', 'people', 'state', 'IN'),
    ('f_role_sales_east_coast', 'people', 'state', 'KY'),
    ('f_role_sales_east_coast', 'people', 'state', 'MA'),
    ('f_role_sales_east_coast', 'people', 'state', 'MD'),
    ('f_role_sales_east_coast', 'people', 'state', 'ME'),
    ('f_role_sales_east_coast', 'people', 'state', 'MI'),
    ('f_role_sales_east_coast', 'people', 'state', 'MS'),
    ('f_role_sales_east_coast', 'people', 'state', 'NC'),
    ('f_role_sales_east_coast', 'people', 'state', 'NH'),
    ('f_role_sales_east_coast', 'people', 'state', 'NJ'),
    ('f_role_sales_east_coast', 'people', 'state', 'NY'),
    ('f_role_sales_east_coast', 'people', 'state', 'OH'),
    ('f_role_sales_east_coast', 'people', 'state', 'PA'),
    ('f_role_sales_east_coast', 'people', 'state', 'RI'),
    ('f_role_sales_east_coast', 'people', 'state', 'SC'),
    ('f_role_sales_east_coast', 'people', 'state', 'TN'),
    ('f_role_sales_east_coast', 'people', 'state', 'VA'),
    ('f_role_sales_east_coast', 'people', 'state', 'VT'),
    ('f_role_sales_east_coast', 'people', 'state', 'WV'),

    -- Sales West Coast (Frodo): AK AR AZ CA CO HI IA ID KS LA MN MO MT ND NE NM NV OK OR SD TX UT WA WI WY
    ('f_role_sales_west_coast', 'people', 'state', 'AK'),
    ('f_role_sales_west_coast', 'people', 'state', 'AR'),
    ('f_role_sales_west_coast', 'people', 'state', 'AZ'),
    ('f_role_sales_west_coast', 'people', 'state', 'CA'),
    ('f_role_sales_west_coast', 'people', 'state', 'CO'),
    ('f_role_sales_west_coast', 'people', 'state', 'HI'),
    ('f_role_sales_west_coast', 'people', 'state', 'IA'),
    ('f_role_sales_west_coast', 'people', 'state', 'ID'),
    ('f_role_sales_west_coast', 'people', 'state', 'KS'),
    ('f_role_sales_west_coast', 'people', 'state', 'LA'),
    ('f_role_sales_west_coast', 'people', 'state', 'MN'),
    ('f_role_sales_west_coast', 'people', 'state', 'MO'),
    ('f_role_sales_west_coast', 'people', 'state', 'MT'),
    ('f_role_sales_west_coast', 'people', 'state', 'ND'),
    ('f_role_sales_west_coast', 'people', 'state', 'NE'),
    ('f_role_sales_west_coast', 'people', 'state', 'NM'),
    ('f_role_sales_west_coast', 'people', 'state', 'NV'),
    ('f_role_sales_west_coast', 'people', 'state', 'OK'),
    ('f_role_sales_west_coast', 'people', 'state', 'OR'),
    ('f_role_sales_west_coast', 'people', 'state', 'SD'),
    ('f_role_sales_west_coast', 'people', 'state', 'TX'),
    ('f_role_sales_west_coast', 'people', 'state', 'UT'),
    ('f_role_sales_west_coast', 'people', 'state', 'WA'),
    ('f_role_sales_west_coast', 'people', 'state', 'WI'),
    ('f_role_sales_west_coast', 'people', 'state', 'WY');

-- ── Role members: human role → functional role(s) ────────────────────────────

CREATE TABLE IF NOT EXISTS rls_role_members (
    personal_role VARCHAR(200) NOT NULL,
    group_role    VARCHAR(200) NOT NULL,
    PRIMARY KEY (personal_role, group_role)
);

INSERT IGNORE INTO rls_role_members VALUES
    ('h_role_bruce', 'f_role_analytics_team'),
    ('h_role_thor',  'f_role_sales_east_coast'),
    ('h_role_frodo', 'f_role_sales_west_coast');

-- ── Secure view: secure_people ────────────────────────────────────────────────
-- 1:1 mirror of PEOPLE with a state-based WHERE clause.
-- This is the only secured object — analogous to a Postgres RLS policy on people.
-- ORDERS, PRODUCTS, REVIEWS have no row restriction; territory filtering happens
-- naturally when any query JOINs through secure_people to get state data.

CREATE OR REPLACE VIEW secure_people AS
SELECT pe.*
FROM PEOPLE pe
WHERE EXISTS (
       SELECT 1 FROM rls_superusers
       WHERE mysql_role = TRIM(BOTH '`' FROM SUBSTRING_INDEX(CURRENT_ROLE(), '@', 1))
   )
   OR EXISTS (
       SELECT 1
       FROM rls_role_members rrm
       JOIN rls_policy rp
         ON  rp.mysql_role    = rrm.group_role
         AND rp.table_name    = 'people'
         AND (rp.filter_value = '*' OR rp.filter_value = pe.state)
       WHERE rrm.personal_role = TRIM(BOTH '`' FROM SUBSTRING_INDEX(CURRENT_ROLE(), '@', 1))
   );

-- ── Grants to functional roles ────────────────────────────────────────────────
-- ORDERS, PRODUCTS, REVIEWS: unrestricted (mirrors Postgres — no RLS policy on these).
-- PEOPLE: blocked; secure_people is the only way to read customer/state data.

GRANT SELECT ON sample.ORDERS         TO 'f_role_analytics_team';
GRANT SELECT ON sample.ORDERS         TO 'f_role_sales_east_coast';
GRANT SELECT ON sample.ORDERS         TO 'f_role_sales_west_coast';
GRANT SELECT ON sample.PRODUCTS       TO 'f_role_analytics_team';
GRANT SELECT ON sample.PRODUCTS       TO 'f_role_sales_east_coast';
GRANT SELECT ON sample.PRODUCTS       TO 'f_role_sales_west_coast';
GRANT SELECT ON sample.REVIEWS        TO 'f_role_analytics_team';
GRANT SELECT ON sample.REVIEWS        TO 'f_role_sales_east_coast';
GRANT SELECT ON sample.REVIEWS        TO 'f_role_sales_west_coast';
GRANT SELECT ON sample.secure_people  TO 'f_role_analytics_team';
GRANT SELECT ON sample.secure_people  TO 'f_role_sales_east_coast';
GRANT SELECT ON sample.secure_people  TO 'f_role_sales_west_coast';
GRANT SELECT ON sample.rls_policy       TO 'f_role_analytics_team';
GRANT SELECT ON sample.rls_policy       TO 'f_role_sales_east_coast';
GRANT SELECT ON sample.rls_policy       TO 'f_role_sales_west_coast';
GRANT SELECT ON sample.rls_role_members TO 'f_role_analytics_team';
GRANT SELECT ON sample.rls_role_members TO 'f_role_sales_east_coast';
GRANT SELECT ON sample.rls_role_members TO 'f_role_sales_west_coast';
GRANT SELECT ON sample.rls_superusers   TO 'f_role_analytics_team';
GRANT SELECT ON sample.rls_superusers   TO 'f_role_sales_east_coast';
GRANT SELECT ON sample.rls_superusers   TO 'f_role_sales_west_coast';

-- PEOPLE is the one secured table — functional roles must go through secure_people.
REVOKE IF EXISTS SELECT ON sample.PEOPLE FROM 'f_role_analytics_team';
REVOKE IF EXISTS SELECT ON sample.PEOPLE FROM 'f_role_sales_east_coast';
REVOKE IF EXISTS SELECT ON sample.PEOPLE FROM 'f_role_sales_west_coast';

-- Remove user-level grants from the metabase connection user on the sample database.
-- In MySQL 8, user-level grants survive SET ROLE and would bypass impersonation.
-- We then re-grant the unrestricted tables explicitly at user level (matching Postgres
-- behavior: ORDERS/PRODUCTS/REVIEWS have no row policy so all rows are always visible).
-- PEOPLE is intentionally not re-granted — access goes through secure_people via role grants.
REVOKE IF EXISTS ALL PRIVILEGES ON sample.* FROM 'metabase'@'%';
GRANT SELECT ON sample.ORDERS   TO 'metabase'@'%';
GRANT SELECT ON sample.PRODUCTS TO 'metabase'@'%';
GRANT SELECT ON sample.REVIEWS  TO 'metabase'@'%';

-- Human roles inherit all grants above through their functional role memberships.
GRANT 'f_role_analytics_team'   TO 'h_role_bruce';
GRANT 'f_role_sales_east_coast' TO 'h_role_thor';
GRANT 'f_role_sales_west_coast' TO 'h_role_frodo';

-- Grant human roles to the Metabase connection user.
GRANT 'h_role_bruce' TO 'metabase'@'%';
GRANT 'h_role_thor'  TO 'metabase'@'%';
GRANT 'h_role_frodo' TO 'metabase'@'%';

-- ── Metabase admin role ───────────────────────────────────────────────────────
-- Base role set in the Metabase DB connection "Role" field. Used for metadata sync
-- and admin (non-impersonated) queries. Listed in rls_superusers — bypasses RLS.

CREATE ROLE IF NOT EXISTS 'metabase_admin';
GRANT SELECT ON sample.ORDERS           TO 'metabase_admin';
GRANT SELECT ON sample.PRODUCTS         TO 'metabase_admin';
GRANT SELECT ON sample.PEOPLE           TO 'metabase_admin';
GRANT SELECT ON sample.REVIEWS          TO 'metabase_admin';
GRANT SELECT ON sample.secure_people    TO 'metabase_admin';
GRANT SELECT ON sample.rls_policy       TO 'metabase_admin';
GRANT SELECT ON sample.rls_role_members TO 'metabase_admin';
GRANT SELECT ON sample.rls_superusers   TO 'metabase_admin';
-- System visibility: active when metabase_admin is the role; not visible under impersonated roles.
GRANT SELECT ON mysql.*              TO 'metabase_admin';
GRANT SELECT ON performance_schema.* TO 'metabase_admin';
GRANT SELECT ON sys.*                TO 'metabase_admin';
GRANT PROCESS ON *.*                 TO 'metabase_admin';
GRANT 'metabase_admin' TO 'metabase'@'%';

FLUSH PRIVILEGES;
