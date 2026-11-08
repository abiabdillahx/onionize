#!/bin/sh
set -eu

HS_DIR="${HS_DIR:-/var/lib/tor/hidden_service}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-30}"
TORRC=/tmp/torrc

[ -n "${TARGET:-}" ] || {
  echo "TARGET is required, e.g. TARGET=app:80" >&2
  exit 1
}

valid_port() {
  case "$1" in
  '' | *[!0-9]*) return 1 ;;
  esac
  [ "${#1}" -le 5 ] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

# True only for a real dotted-quad. Keeps junk like '1.2.3', '999.1.1.1', '...'
# and '' out of the torrc, so the user gets our error, not a Tor parse error.
is_ipv4() {
  case "$1" in
  '' | *[!0-9.]*) return 1 ;;
  esac
  oldifs=$IFS
  IFS=.
  # shellcheck disable=SC2086 # deliberate split on dots
  set -- $1
  IFS=$oldifs
  [ $# -eq 4 ] || return 1
  for octet in "$@"; do
    case "$octet" in
    '' | *[!0-9]*) return 1 ;;
    esac
    [ "${#octet}" -le 3 ] && [ "$octet" -le 255 ] || return 1
  done
  return 0
}

# Tor resolves HiddenServicePort targets once at startup, so resolve here
# (retrying) to survive the app container coming up a bit later.
resolve() {
  if is_ipv4 "$1"; then
    echo "$1"
    return 0
  fi
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

bad_entry() {
  echo "bad TARGET entry '$1': $2" >&2
  echo "expected host:port or onionport:host:port (ports 1-65535, IPv4 only)" >&2
  exit 1
}

{
  echo "DataDirectory /var/lib/tor"
  echo "SocksPort 0"
  echo "Log notice stdout"
  echo "HiddenServiceDir $HS_DIR"
} >"$TORRC"

used_vports=""
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
    bad_entry "$entry" "wrong number of ':' separators"
    ;;
  esac

  [ -n "$host" ] || bad_entry "$entry" "empty host"
  # All-numeric host that is not a real dotted-quad: reject outright rather than
  # handing it to DNS, which would either stall for WAIT_TIMEOUT or silently
  # coerce it via inet_aton (e.g. '1.2.3' -> 1.2.0.3).
  case "$host" in
  *[!0-9.]*) ;;
  *) is_ipv4 "$host" || bad_entry "$entry" "'$host' is not a valid IPv4 address" ;;
  esac
  valid_port "$port" || bad_entry "$entry" "invalid target port '$port'"
  valid_port "$vport" || bad_entry "$entry" "invalid onion port '$vport'"

  case " $used_vports " in
  *" $vport "*) bad_entry "$entry" "onion port $vport is already used by another entry" ;;
  esac
  used_vports="$used_vports $vport"

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
