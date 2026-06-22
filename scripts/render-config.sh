#!/bin/sh
# ---------------------------------------------------------------------------
# Render config/config.json from a .env file and config/config.json.template.
#
#   usage: scripts/render-config.sh [ENV_FILE] [TEMPLATE] [OUTPUT]
#   defaults:  ENV_FILE = <repo>/.env
#              TEMPLATE = <repo>/config/config.json.template
#              OUTPUT   = <repo>/config/config.json
#
# Only the parameters documented in .env.example are configurable; everything
# else is baked into the template as a default. INBOUND_MODE is always "both"
# (the template ships both a tun and a mixed inbound), so it is not read here.
# ---------------------------------------------------------------------------
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(dirname -- "$SCRIPT_DIR")

ENV_FILE=${1:-"$ROOT_DIR/.env"}
TEMPLATE=${2:-"$ROOT_DIR/config/config.json.template"}
OUTPUT=${3:-"$ROOT_DIR/config/config.json"}

[ -f "$ENV_FILE" ] || { echo "render-config: env file not found: $ENV_FILE" >&2; exit 1; }
[ -f "$TEMPLATE" ] || { echo "render-config: template not found: $TEMPLATE" >&2; exit 1; }

# ----- load .env ------------------------------------------------------------
# KEY=VALUE lines only; "#" comments and blank lines skipped; CR stripped so a
# CRLF .env edited on Windows still parses.
while IFS= read -r raw || [ -n "$raw" ]; do
    raw=$(printf '%s' "$raw" | tr -d '\r')
    case "$raw" in
        ''|\#*) continue ;;
        *=*) ;;
        *) continue ;;
    esac
    key=$(printf '%s' "${raw%%=*}" | tr -d ' \t')
    val=${raw#*=}
    val=$(printf '%s' "$val" | sed 's/^[ \t]*//; s/[ \t]*$//')
    case "$val" in
        \"*\") val=${val#\"}; val=${val%\"} ;;
        \'*\') val=${val#\'}; val=${val%\'} ;;
    esac
    case "$key" in
        [A-Za-z_]*) export "$key=$val" ;;
    esac
done < "$ENV_FILE"

# ----- defaults (for anything .env did not set) -----------------------------
: "${PROXY_PORT:=8888}"
: "${LISTEN_ADDR:=0.0.0.0}"
: "${EXT_SERVER:=}"
: "${EXT_PORT:=8080}"
: "${EXT_USERNAME:=}"
: "${EXT_PASSWORD:=}"
: "${EXT_TLS:=false}"
: "${EXT_TLS_INSECURE:=false}"
: "${DNS_TYPE:=https}"
: "${DNS_SERVER:=1.1.1.1}"
: "${LOG_LEVEL:=info}"
: "${TUN_ADDR:=192.168.30.1/30}"

json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# ----- dns-remote server object ---------------------------------------------
case "$DNS_TYPE" in
    local)
        R_DNS_REMOTE='{ "type": "local", "tag": "dns-remote" }' ;;
    https|tls|udp|tcp)
        R_DNS_REMOTE="{ \"type\": \"$DNS_TYPE\", \"tag\": \"dns-remote\", \"server\": \"$(json_escape "$DNS_SERVER")\" }" ;;
    *)
        echo "render-config: unknown DNS_TYPE='$DNS_TYPE' (use: https, tls, udp, tcp, local)" >&2
        exit 1 ;;
esac

# ----- optional auth / tls fragments ----------------------------------------
if [ -n "$EXT_USERNAME" ]; then
    R_EXT_AUTH=", \"username\": \"$(json_escape "$EXT_USERNAME")\", \"password\": \"$(json_escape "$EXT_PASSWORD")\""
else
    R_EXT_AUTH=""
fi

if [ "$EXT_TLS" = "true" ]; then
    R_EXT_TLS=", \"tls\": { \"enabled\": true, \"server_name\": \"$(json_escape "$EXT_SERVER")\", \"insecure\": $EXT_TLS_INSECURE }"
else
    R_EXT_TLS=""
fi

[ -n "$EXT_SERVER" ] || echo "render-config: WARNING EXT_SERVER is empty -> external outbound has no server." >&2

# ----- substitute -----------------------------------------------------------
R_LOG_LEVEL=$LOG_LEVEL
R_TUN_ADDR=$TUN_ADDR
R_LISTEN_ADDR=$LISTEN_ADDR
R_PROXY_PORT=$PROXY_PORT
R_EXT_SERVER=$(json_escape "$EXT_SERVER")
R_EXT_PORT=$EXT_PORT
export R_LOG_LEVEL R_DNS_REMOTE R_TUN_ADDR R_LISTEN_ADDR R_PROXY_PORT R_EXT_SERVER R_EXT_PORT R_EXT_AUTH R_EXT_TLS

TMP=$(mktemp)
awk '
function repl(s, tok, val,    out, p) {
    out = ""
    while ((p = index(s, tok)) > 0) {
        out = out substr(s, 1, p - 1) val
        s = substr(s, p + length(tok))
    }
    return out s
}
{
    line = $0
    line = repl(line, "__LOG_LEVEL__",   ENVIRON["R_LOG_LEVEL"])
    line = repl(line, "__DNS_REMOTE__",  ENVIRON["R_DNS_REMOTE"])
    line = repl(line, "__TUN_ADDR__",    ENVIRON["R_TUN_ADDR"])
    line = repl(line, "__LISTEN_ADDR__", ENVIRON["R_LISTEN_ADDR"])
    line = repl(line, "__PROXY_PORT__",  ENVIRON["R_PROXY_PORT"])
    line = repl(line, "__EXT_SERVER__",  ENVIRON["R_EXT_SERVER"])
    line = repl(line, "__EXT_PORT__",    ENVIRON["R_EXT_PORT"])
    line = repl(line, "__EXT_AUTH__",    ENVIRON["R_EXT_AUTH"])
    line = repl(line, "__EXT_TLS__",     ENVIRON["R_EXT_TLS"])
    sub(/[ \t]+$/, "", line)   # an empty auth/tls fragment leaves a blank line
    print line
}
' "$TEMPLATE" > "$TMP"

mv "$TMP" "$OUTPUT"
echo "render-config: wrote $OUTPUT"
