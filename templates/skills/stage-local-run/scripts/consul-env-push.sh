#!/usr/bin/env bash
# Upload KEY=VALUE lines from ENV_FILE to Consul KV under BASE_PATH.
set -euo pipefail

: "${CONSUL_ADDR:?Set CONSUL_ADDR (your Consul URL, for example in ~/.zshrc)}"
CONSUL_DC="${CONSUL_DC:-ap-south-1}"
: "${BASE_PATH:?Set BASE_PATH (for example configs/stage/<service>)}"
: "${ENV_FILE:?Set ENV_FILE (for example ~/.config/agent-envs/<service>.stage.env)}"
: "${CONSUL_TOKEN:?Set CONSUL_TOKEN env var (your Consul ACL token)}"

BASE_PATH="${BASE_PATH%/}"
[[ -f "$ENV_FILE" ]] || { echo "❌ '$ENV_FILE' not found"; exit 1; }

trim() { printf '%s' "$1" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g'; }

keys=()
vals=()
while IFS= read -r line || [[ -n "$line" ]]; do
  line="$(trim "$line")"
  [[ -z "$line" || "$line" =~ ^# ]] && continue
  line="$(printf '%s' "$line" | sed -E 's/^export[[:space:]]+//')"
  [[ "$line" != *"="* ]] && continue

  KEY="$(trim "${line%%=*}")"
  VAL="$(trim "${line#*=}")"

  # Strip surrounding quotes; undo the '\'' escapes that the pull script writes.
  if [[ "$VAL" =~ ^\".*\"$ ]]; then
    VAL="${VAL#\"}"; VAL="${VAL%\"}"
  elif [[ "$VAL" =~ ^\'.*\'$ ]]; then
    VAL="${VAL#\'}"; VAL="${VAL%\'}"
    VAL="${VAL//\'\\\'\'/\'}"
  fi

  if [[ ! "$KEY" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    echo "❌ Invalid env key '$KEY'"; exit 1
  fi
  keys+=("$KEY")
  vals+=("$VAL")
done <"$ENV_FILE"

[[ ${#keys[@]} -gt 0 ]] || { echo "❌ No keys in '$ENV_FILE'"; exit 1; }

echo "Push ${#keys[@]} keys from '$ENV_FILE' to:"
echo "    $CONSUL_ADDR (dc=$CONSUL_DC)"
echo "    base path: $BASE_PATH"
if [[ "${YES:-}" != "1" ]]; then
  read -r -p "Continue? [y/N] " answer
  [[ "$answer" == "y" || "$answer" == "Y" ]] || { echo "Aborted."; exit 1; }
fi

for i in "${!keys[@]}"; do
  # The token goes through stdin so it stays out of the process list.
  HTTP_CODE="$(printf 'X-Consul-Token: %s\n' "$CONSUL_TOKEN" |
    curl -sS -o /dev/null -w "%{http_code}" -H @- -X PUT \
      "$CONSUL_ADDR/v1/kv/$BASE_PATH/${keys[$i]}?dc=$CONSUL_DC" \
      --data-binary "${vals[$i]}")"
  if [[ "$HTTP_CODE" == "200" ]]; then
    echo "✅ ${keys[$i]}"
  else
    echo "❌ ${keys[$i]} (HTTP $HTTP_CODE)"; exit 1
  fi
done

echo "🎉 Done."
