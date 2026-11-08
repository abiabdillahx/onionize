#!/bin/sh
set -eu

HS_DIR="${HS_DIR:-/var/lib/tor/hidden_service}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-30}"
TORRC=/tmp/torrc

[ -n "${TARGET:-}" ] || {
  echo "TARGET is required, e.g. TARGET=app:80" >&2
  exit 1
}

# Tor resolves HiddenServicePort targets once at startup, so resolve here
# (retrying) to survive the app container coming up a bit later.
resolve() {
  case "$1" in
  *[!0-9.]*) ;; # contains non-digit/dot -> hostname
  *)
    echo "$1"
    return 0
    ;; # already an IPv4
  esac
  i=0
  while [ "$i" -lt "$WAIT_TIMEOUT" ]; do
    ip=$(getent ahostsv4 "$1" 2>/dev/null | awk 'NR==1{print $1}')
    if [ -n "$ip" ]; then
      echo "$ip"
      return 0
    fi
    i=$((i + 1))
    sleep 1
  done
  return 1
}

{
  echo "DataDirectory /var/lib/tor"
  echo "SocksPort 0"
  echo "Log notice stdout"
  echo "HiddenServiceDir $HS_DIR"
} >"$TORRC"

for entry in $(echo "$TARGET" | tr ',' ' '); do
  colons=$(printf %s "$entry" | tr -cd ':' | wc -c)
  case "$colons" in
  1)
    vport=80
    host=${entry%%:*}
    port=${entry##*:}
    ;;
  2)
    vport=${entry%%:*}
    rest=${entry#*:}
    host=${rest%%:*}
    port=${rest##*:}
    ;;
  *)
    echo "bad TARGET entry '$entry' (use host:port or onionport:host:port)" >&2
    exit 1
    ;;
  esac
  ip=$(resolve "$host") || {
    echo "cannot resolve '$host' after ${WAIT_TIMEOUT}s" >&2
    exit 1
  }
  echo "HiddenServicePort $vport $ip:$port" >>"$TORRC"
done

# Print the .onion address once Tor has generated it.
(
  while [ ! -s "$HS_DIR/hostname" ]; do sleep 1; done
  echo "onion address: $(cat "$HS_DIR/hostname")"
) &

exec tor -f "$TORRC"
