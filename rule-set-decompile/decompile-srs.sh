#!/bin/sh
# ---------------------------------------------------------------------------
# Decompile a sing-box rule-set (.srs) into readable JSON.
#
#   usage: decompile-srs.sh <URL|FILE> [OUTPUT]
#   examples:
#     decompile-srs.sh https://example.com/russia_inside.srs
#     decompile-srs.sh ./telegram.srs telegram.json
#
# SOURCE may be an http(s) URL or a local .srs file. The JSON is always written
# to a file: OUTPUT when given, otherwise <source-name>.json in the current dir.
#
# Decompiling runs inside the sing-box Docker image (override with SINGBOX_IMAGE).
# ---------------------------------------------------------------------------
set -eu

IMAGE=${SINGBOX_IMAGE:-itdoginfo/sing-box:v1.13.13}

SOURCE=${1:-}
OUTPUT=${2:-}

[ -n "$SOURCE" ] || { echo "decompile-srs: usage: $0 <URL|FILE> [OUTPUT]" >&2; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "decompile-srs: docker not found in PATH" >&2; exit 1; }

# Default OUTPUT: the source file name with a .json extension, in the cwd.
if [ -z "$OUTPUT" ]; then
    base=${SOURCE%%\?*}        # drop any ?query from a URL
    base=${base##*/}           # keep the last path segment
    base=${base%.srs}          # drop a trailing .srs
    [ -n "$base" ] || base=ruleset
    OUTPUT="$base.json"
fi

# ----- workspace mounted into the container --------------------------------
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# ----- obtain the .srs ------------------------------------------------------
case "$SOURCE" in
    http://*|https://*)
        command -v curl >/dev/null 2>&1 || { echo "decompile-srs: curl not found in PATH" >&2; exit 1; }
        curl -fsSL -o "$WORK/input.srs" "$SOURCE" \
            || { echo "decompile-srs: failed to download: $SOURCE" >&2; exit 1; } ;;
    *)
        [ -f "$SOURCE" ] || { echo "decompile-srs: file not found: $SOURCE" >&2; exit 1; }
        cp -- "$SOURCE" "$WORK/input.srs" ;;
esac

# ----- decompile ------------------------------------------------------------
docker run --rm -v "$WORK:/data" --entrypoint sing-box "$IMAGE" \
    rule-set decompile --output /data/output.json /data/input.srs >&2 \
    || { echo "decompile-srs: sing-box decompile failed" >&2; exit 1; }

# ----- deliver --------------------------------------------------------------
cp -- "$WORK/output.json" "$OUTPUT"
echo "decompile-srs: wrote $OUTPUT" >&2
