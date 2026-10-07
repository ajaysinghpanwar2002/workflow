#!/usr/bin/env bash
# Download Consul KV keys under BASE_PATH into a sourceable env file.
set -euo pipefail

: "${CONSUL_ADDR:?Set CONSUL_ADDR (your Consul URL, for example in ~/.zshrc)}"
CONSUL_DC="${CONSUL_DC:-ap-south-1}"
: "${BASE_PATH:?Set BASE_PATH (for example configs/stage/<service>)}"
: "${OUT_FILE:?Set OUT_FILE (for example ~/.config/agent-envs/<service>.stage.env)}"
: "${CONSUL_TOKEN:?Set CONSUL_TOKEN env var (your Consul ACL token)}"

BASE_PATH="${BASE_PATH%/}"
umask 077
mkdir -p "$(dirname "$OUT_FILE")"
tmp="$(mktemp "$OUT_FILE.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

# The token goes through stdin so it stays out of the process list.
printf 'X-Consul-Token: %s\n' "$CONSUL_TOKEN" |
  curl -fsS -H @- "$CONSUL_ADDR/v1/kv/$BASE_PATH/?recurse=true&dc=$CONSUL_DC" |
  jq -r --arg prefix "$BASE_PATH/" '
    .[]
    | select(.Key | endswith("/") | not)
    | (.Key | ltrimstr($prefix)) as $key
    | select($key | test("^[A-Za-z_][A-Za-z0-9_]*$"))
    | "\($key)=\(.Value // "" | @base64d | @sh)"' >"$tmp"

count="$(wc -l <"$tmp" | tr -d ' ')"
[ "$count" -gt 0 ] || { echo "No keys found under $BASE_PATH" >&2; exit 1; }
mv "$tmp" "$OUT_FILE"
trap - EXIT
echo "Wrote $count keys to $OUT_FILE"
