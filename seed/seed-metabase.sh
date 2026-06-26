#!/usr/bin/env bash
set -euo pipefail

METABASE_PORT="${METABASE_PORT:-3300}"
API_KEY="mb_aDqk1Tc4ZotWb2TyjHY71glALKlBg75dLgmSufWGLc="
BASE_URL="http://127.0.0.1:${METABASE_PORT}"

api() {
  local method="$1" endpoint="$2" payload="${3:-}"
  if [[ -n "$payload" ]]; then
    curl -fsS -X "$method" "${BASE_URL}${endpoint}" \
      -H "Content-Type: application/json" \
      -H "x-api-key: ${API_KEY}" \
      -d "$payload"
  else
    curl -fsS -X "$method" "${BASE_URL}${endpoint}" \
      -H "x-api-key: ${API_KEY}"
  fi
}

echo "Waiting for Metabase API key to become active..."
attempt=0
until api GET "/api/user/current" >/dev/null 2>&1; do
  attempt=$((attempt + 1))
  [[ $attempt -ge 40 ]] && { echo "Timed out waiting for Metabase." >&2; exit 1; }
  sleep 3
done

# ── Database ──────────────────────────────────────────────────────────────────

echo "Waiting for sample_mysql database to sync..."
db_id=""
attempt=0
while [[ -z "$db_id" ]]; do
  db_id="$(api GET "/api/database" | jq -r '.data[]? | select(.name == "sample_mysql") | .id' | head -1)"
  attempt=$((attempt + 1))
  [[ $attempt -ge 30 ]] && { echo "Database sample_mysql not found." >&2; exit 1; }
  [[ -z "$db_id" ]] && sleep 3
done
echo "Database ID: ${db_id}"

# ── Groups ────────────────────────────────────────────────────────────────────

groups_json="$(api GET "/api/permissions/group")"

ensure_group() {
  local name="$1"
  local id
  id="$(echo "$groups_json" | jq -r --arg n "$name" '.[] | select(.name == $n) | .id' | head -1)"
  if [[ -z "$id" ]]; then
    id="$(api POST "/api/permissions/group" "{\"name\":\"${name}\"}" | jq -r '.id')"
    groups_json="$(api GET "/api/permissions/group")"
  fi
  echo "$id"
}

analytics_group_id="$(ensure_group "Analytics Team")"
sales_east_group_id="$(ensure_group "Sales East Coast")"
sales_west_group_id="$(ensure_group "Sales West Coast")"

# ── Users ─────────────────────────────────────────────────────────────────────

users_json="$(api GET "/api/user")"

user_id_by_email() {
  echo "$users_json" | jq -r --arg e "$1" \
    'if type == "array" then . elif .data then .data else [] end | .[] | select(.email == $e) | .id' | head -1
}

bruce_id="$(user_id_by_email "bruce@example.com")"
thor_id="$(user_id_by_email "thor@example.com")"
frodo_id="$(user_id_by_email "frodo@example.com")"

# ── User attributes ───────────────────────────────────────────────────────────
# db_role is the personal MySQL role Metabase activates via SET ROLE.
# The RLS Users group tells Metabase to read this attribute; the value is per-user.

set_db_role() {
  local user_id="$1" role_name="$2"
  [[ -z "$user_id" ]] && return
  api PUT "/api/user/${user_id}" "{\"login_attributes\":{\"db_role\":\"${role_name}\"}}" >/dev/null
}

[[ -n "$bruce_id" ]] && set_db_role "$bruce_id" "h_role_bruce"
[[ -n "$thor_id" ]]  && set_db_role "$thor_id"  "h_role_thor"
[[ -n "$frodo_id" ]] && set_db_role "$frodo_id" "h_role_frodo"

# ── Group membership ──────────────────────────────────────────────────────────

ensure_membership() {
  local user_id="$1" group_id="$2"
  [[ -z "$user_id" || -z "$group_id" ]] && return
  local already
  already="$(api GET "/api/permissions/group/${group_id}" | jq -r --argjson u "$user_id" '.members[]? | select(.user_id == $u) | .user_id')"
  [[ -n "$already" ]] && return
  api POST "/api/permissions/membership" "{\"user_id\":${user_id},\"group_id\":${group_id}}" >/dev/null
}

[[ -n "$bruce_id" ]] && ensure_membership "$bruce_id" "$analytics_group_id"
[[ -n "$thor_id" ]]  && ensure_membership "$thor_id"  "$sales_east_group_id"
[[ -n "$frodo_id" ]] && ensure_membership "$frodo_id" "$sales_west_group_id"

# ── Connection impersonation ──────────────────────────────────────────────────
# Two steps: (1) set the role attribute name on the DB connection so Metabase
# knows which user attribute to read; (2) set RLS Users group to impersonated
# on this database via the permissions graph.

api PUT "/api/database/${db_id}" "$(jq -nc \
  '{is_on_demand:false,is_full_sync:true,is_sample:false,auto_run_queries:true,
    name:"sample_mysql",engine:"mysql",
    details:{host:"mysql",port:3306,dbname:"sample",user:"metabase",
             password:"metasample123",role:"metabase_admin",ssl:false,
             "tunnel-enabled":false,"advanced-options":false}}')" >/dev/null

revision="$(api GET "/api/permissions/graph" | jq -r '.revision')"
api PUT "/api/permissions/graph" "$(jq -nc \
  --argjson analytics "$analytics_group_id" \
  --argjson east      "$sales_east_group_id" \
  --argjson west      "$sales_west_group_id" \
  --argjson db        "$db_id" \
  --argjson rev       "$revision" \
  '{revision:$rev,sandboxes:[],
    impersonations:[
      {attribute:"db_role",db_id:$db,group_id:$analytics},
      {attribute:"db_role",db_id:$db,group_id:$east},
      {attribute:"db_role",db_id:$db,group_id:$west}
    ],
    groups:{
      "1":                   {($db|tostring):{"view-data":"blocked","create-queries":"no",download:{schemas:"full"}}},
      ($analytics|tostring): {($db|tostring):{"view-data":"impersonated","create-queries":"query-builder-and-native",download:{schemas:"full"}}},
      ($east|tostring):      {($db|tostring):{"view-data":"impersonated","create-queries":"query-builder-and-native",download:{schemas:"full"}}},
      ($west|tostring):      {($db|tostring):{"view-data":"impersonated","create-queries":"query-builder-and-native",download:{schemas:"full"}}}
    }}')" >/dev/null

echo "Connection impersonation configured."

# ── Collection ────────────────────────────────────────────────────────────────

collection_id="$(api GET "/api/collection" | jq -r '.[] | select(.name == "RLS Demo") | .id' | head -1)"
if [[ -z "$collection_id" ]]; then
  collection_id="$(api POST "/api/collection" \
    '{"name":"RLS Demo","description":"MySQL connection impersonation demo cards."}' | jq -r '.id')"
fi

# ── Cards ─────────────────────────────────────────────────────────────────────

create_card_if_missing() {
  local name="$1" display="$2" description="$3" query="$4" viz_settings="${5:-}"
  local existing
  existing="$(api GET "/api/collection/${collection_id}/items" \
    | jq -r --arg n "$name" '.data[]? | select(.model == "card" and .name == $n) | .id' | head -1)"
  [[ -n "$existing" ]] && { echo "$existing"; return; }
  local payload
  if [[ -n "$viz_settings" ]]; then
    payload="$(jq -nc \
      --arg name "$name" --arg display "$display" --arg desc "$description" \
      --argjson cid "$collection_id" --argjson q "$query" --argjson viz "$viz_settings" \
      '{name:$name,display:$display,description:$desc,collection_id:$cid,dataset_query:$q,visualization_settings:$viz}')"
  else
    payload="$(jq -nc \
      --arg name "$name" --arg display "$display" --arg desc "$description" \
      --argjson cid "$collection_id" --argjson q "$query" \
      '{name:$name,display:$display,description:$desc,collection_id:$cid,dataset_query:$q,visualization_settings:{}}')"
  fi
  api POST "/api/card" "$payload" | jq -r '.id'
}

active_role_card_id="$(create_card_if_missing \
  "Active Role" "table" \
  "Shows which personal MySQL role Metabase activated for this session via SET ROLE." \
  "$(jq -nc --argjson db "$db_id" \
    '{type:"native",database:$db,native:{query:"SELECT\n  TRIM(BOTH '\''`'\'' FROM SUBSTRING_INDEX(CURRENT_ROLE(), '\''@'\'', 1)) AS personal_role,\n  DATABASE() AS connected_db,\n  NOW() AS checked_at","template-tags":{}}}')")"

team_card_id="$(create_card_if_missing \
  "My Team Memberships" "table" \
  "Shows team role(s) for this personal role, or 'superuser' for system accounts." \
  "$(jq -nc --argjson db "$db_id" \
    '{type:"native",database:$db,native:{query:"SELECT '\''superuser'\'' AS team_role\nFROM rls_superusers\nWHERE mysql_role = TRIM(BOTH '\''`'\'' FROM SUBSTRING_INDEX(CURRENT_ROLE(), '\''@'\'', 1))\nUNION ALL\nSELECT group_role AS team_role\nFROM rls_role_members\nWHERE personal_role = TRIM(BOTH '\''`'\'' FROM SUBSTRING_INDEX(CURRENT_ROLE(), '\''@'\'', 1))","template-tags":{}}}')")"

# Delete My Orders if it exists from a previous seed run
old_orders_id="$(api GET "/api/collection/${collection_id}/items" \
  | jq -r '.data[]? | select(.model == "card" and .name == "My Orders") | .id' | head -1)"
[[ -n "$old_orders_id" ]] && api DELETE "/api/card/${old_orders_id}" >/dev/null 2>&1 || true

by_state_card_id="$(create_card_if_missing \
  "Orders by State" "map" \
  "Order count per state — ORDERS joined to secure_people for territory filtering. Bruce sees 50 states, Thor 25 east, Frodo 25 west." \
  "$(jq -nc --argjson db "$db_id" \
    '{type:"native",database:$db,native:{query:"SELECT p.state,\n       COUNT(*) AS orders,\n       ROUND(SUM(o.total), 2) AS revenue\nFROM ORDERS o\nJOIN secure_people p ON p.id = o.user_id\nGROUP BY p.state\nORDER BY orders DESC","template-tags":{}}}')" \
  '{"map.type":"region","map.region":"us_states","map.metric_column":"orders","map.dimension_column":"state"}')"

# ── Dashboard ─────────────────────────────────────────────────────────────────

dashboard_id="$(api GET "/api/collection/${collection_id}/items" \
  | jq -r '.data[]? | select(.model == "dashboard" and .name == "RLS Demo") | .id' | head -1)"

if [[ -z "$dashboard_id" ]]; then
  dashboard_id="$(api POST "/api/dashboard" \
    "$(jq -nc --argjson cid "$collection_id" \
      '{name:"RLS Demo",description:"Demonstrates MySQL row-level security via Metabase connection impersonation.",collection_id:$cid,parameters:[]}')" \
    | jq -r '.id')"
fi

add_card() {
  local dash_id="$1" card_id="$2" row="$3" col="$4" sx="$5" sy="$6"
  local dash
  dash="$(api GET "/api/dashboard/${dash_id}")"
  echo "$dash" | jq -e --argjson cid "$card_id" '.dashcards[]? | select(.card_id == $cid)' >/dev/null 2>&1 && return
  api PUT "/api/dashboard/${dash_id}" \
    "$(echo "$dash" | jq -c \
      --argjson cid "$card_id" --argjson r "$row" --argjson c "$col" \
      --argjson sx "$sx" --argjson sy "$sy" \
      '.dashcards = ((.dashcards // []) + [{id:-1,card_id:$cid,row:$r,col:$c,size_x:$sx,size_y:$sy,parameter_mappings:[],visualization_settings:{}}])')" \
    >/dev/null
}

# Row 0: Active Role (left) | My Team Memberships (right)
add_card "$dashboard_id" "$active_role_card_id" 0  0  12 4
add_card "$dashboard_id" "$team_card_id"        0 12  12 4
# Row 4: Orders by State (full width — the money shot)
add_card "$dashboard_id" "$by_state_card_id"    4  0  24 12

echo "Metabase seed complete."
