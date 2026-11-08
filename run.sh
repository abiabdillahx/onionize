#!/usr/bin/env bash
# Interactive setup: generates an onionize compose file and starts it.
set -euo pipefail

IMAGE_DEFAULT="ghcr.io/abiabdillahx/onionize"

die() {
  echo "error: $*" >&2
  exit 1
}

ask() { # ask "prompt" "default" -> ANS
  local a
  if [ -n "${2:-}" ]; then
    read -r -p "$1 [$2]: " a
    ANS="${a:-$2}"
  else
    read -r -p "$1: " a
    ANS="$a"
  fi
}

choose() { # choose "prompt" item... -> PICK
  local prompt="$1"
  shift
  local items=("$@") n=$# i a
  [ "$n" -gt 0 ] || die "nothing to choose from"
  echo "$prompt"
  for i in "${!items[@]}"; do printf '  %d) %s\n' $((i + 1)) "${items[$i]}"; done
  while true; do
    read -r -p "> " a
    if [[ "$a" =~ ^[0-9]+$ ]] && [ "$a" -ge 1 ] && [ "$a" -le "$n" ]; then
      PICK="${items[$((a - 1))]}"
      return
    fi
    echo "pick 1-$n"
  done
}

yesno() { # yesno "prompt" y|n -> exit 0 if yes
  local hint="[y/N]" a
  [ "$2" = y ] && hint="[Y/n]"
  read -r -p "$1 $hint " a
  a="${a:-$2}"
  [[ "$a" =~ ^[Yy] ]]
}

valid_port() { [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]; }

ask_port() { # ask_port "prompt" "default" -> ANS
  while true; do
    ask "$1" "${2:-}"
    valid_port "$ANS" && return
    echo "enter a port between 1 and 65535"
  done
}

in_array() {
  local x="$1"
  shift
  local y
  for y in "$@"; do [ "$x" = "$y" ] && return 0; done
  return 1
}

host_ports() { # every port that belongs to a host (non-container) target
  local t
  for t in "${targets[@]}"; do
    case "$t" in *:host.docker.internal:*) echo "${t##*:}" ;; esac
  done
}

firewall_hint() { # best-effort name of whatever is likely dropping the packets
  if systemctl is-active --quiet ufw 2>/dev/null; then
    echo "sudo ufw allow in on docker0 to any port $1 proto tcp"
  elif systemctl is-active --quiet firewalld 2>/dev/null; then
    echo "sudo firewall-cmd --permanent --zone=trusted --add-interface=docker0 && sudo firewall-cmd --reload"
  else
    echo "allow TCP from the docker bridge (172.17.0.0/16) to port $1 on the host"
  fi
}

reachable_from_container() { # reachable_from_container IMAGE PORT
  docker run --rm --add-host probe.host:host-gateway --entrypoint sh "$1" -c \
    "nc -z -w4 probe.host $2" >/dev/null 2>&1
}

reachable_from_host() { # reachable_from_host ADDR PORT  (bash /dev/tcp, no extra tools)
  timeout 3 bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null
}

banner() {
  if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    echo -e "\033[0;36m▄\033[0;96m▀\033[0;97m▀▄\033[0;37m  \033[0;36m▓\033[0;96m▀\033[0;97m▀▄\033[0;37m  \033[0;90m▀\033[0;36m▀█\033[0;96m▀\033[0;97m▀\033[0;37m \033[0;36m▄\033[0;96m▀\033[0;97m▀▄\033[0;37m  \033[0;36m▓\033[0;96m▀\033[0;97m▀▄\033[0;37m  \033[0;90m▀\033[0;36m▀█\033[0;96m▀\033[0;97m▀\033[0;37m \033[0;90m▀\033[0;36m▀▀\033[0;96m▀\033[0;97;46m▀\033[0;37m \033[0;36m▄▀▀\033[0;96m▀\033[0;97m▀\033[0m"
    echo -e "\033[0;36m▒\033[0;37m   \033[0;96;46m▀\033[0;37m \033[0;36m▒\033[0;37m   \033[0;96;46m▀\033[0;37m   \033[0;36m▓\033[0;37m   \033[0;36m▒\033[0;37m   \033[0;96;46m▀\033[0;37m \033[0;36m▒\033[0;37m   \033[0;96;46m▀\033[0;37m   \033[0;36m▓\033[0;37m   ▄\033[0;96m▀\033[0;36m▀▀\033[0;90m▀\033[0;37m \033[0;36m▓▀\033[0;90m▀\033[0;37m  \033[0m"
    echo -e "\033[0;36m▀▄▄▄▀\033[0;37m \033[0;36m░\033[0;37m   \033[0;36m█\033[0;37m \033[0;90m▄\033[0;36m▄▒\033[0;90m▄▄\033[0;37m \033[0;36m▀▄▄▄▀\033[0;37m \033[0;36m░\033[0;37m   \033[0;36m█\033[0;37m \033[0;90m▄\033[0;36m▄▒\033[0;90m▄▄\033[0;37m \033[0;36m▀▄▄▄\033[0;90m▄\033[0;37m \033[0;36m░▄▄▄\033[0;90m▄\033[0m"
  else
    cat <<'BANNER'
▄▀▀▄  ▓▀▀▄  ▀▀█▀▀ ▄▀▀▄  ▓▀▀▄  ▀▀█▀▀ ▀▀▀▀▀ ▄▀▀▀▀
▒   ▀ ▒   ▀   ▓   ▒   ▀ ▒   ▀   ▓   ▄▀▀▀▀ ▓▀▀  
▀▄▄▄▀ ░   █ ▄▄▒▄▄ ▀▄▄▄▀ ░   █ ▄▄▒▄▄ ▀▄▄▄▄ ░▄▄▄▄
BANNER
  fi
  echo
  echo "  expose any Docker service as a Tor onion service"
  echo
}

banner

command -v docker >/dev/null || die "docker not found"
docker info >/dev/null 2>&1 || die "cannot talk to the Docker daemon (not running, or no permission?)"

targets=()
nets=()
used=()
has_host=0

while true; do
  choose "Where does the service run?" "Docker container" "Directly on this host"

  if [ "$PICK" = "Docker container" ]; then
    mapfile -t netlist < <(docker network ls --format '{{.Name}}' | grep -Ev '^(bridge|host|none)$' || true)
    [ "${#netlist[@]}" -gt 0 ] || die "no user-defined Docker networks found (start your containers with compose first)"
    choose "Which Docker network?" "${netlist[@]}"
    net="$PICK"

    mapfile -t cl < <(docker ps --filter "network=$net" --format '{{.Names}}')
    [ "${#cl[@]}" -gt 0 ] || die "no running containers on network '$net'"
    choose "Which container?" "${cl[@]}"
    host="$PICK"

    mapfile -t ports < <(docker inspect --format '{{range $p, $_ := .Config.ExposedPorts}}{{println $p}}{{end}}' "$host" |
      sed 's#/.*##' | grep -v '^$' | sort -un || true)
    if [ "${#ports[@]}" -eq 1 ]; then
      ask_port "Container port (internal, not the published one)" "${ports[0]}"
    elif [ "${#ports[@]}" -gt 1 ]; then
      choose "Which container port?" "${ports[@]}"
      ask_port "Container port" "$PICK"
    else ask_port "Container port (no EXPOSE found in image)" ""; fi
    port="$ANS"

    in_array "$net" "${nets[@]+"${nets[@]}"}" || nets+=("$net")
  else
    has_host=1
    host="host.docker.internal"
    ask_port "Port on the host" ""
    port="$ANS"
    echo "note: the app must listen on 0.0.0.0 (or the docker bridge IP), not 127.0.0.1."
  fi

  dv=80
  in_array "$dv" "${used[@]+"${used[@]}"}" && dv="$port"
  while true; do
    ask_port "Onion port (what visitors use)" "$dv"
    in_array "$ANS" "${used[@]+"${used[@]}"}" || break
    echo "onion port $ANS is already used by another service"
  done
  vport="$ANS"

  targets+=("$vport:$host:$port")
  used+=("$vport")
  yesno "Add another service?" n || break
done

ask "Image" "$IMAGE_DEFAULT"
image="$ANS"

# A host target has to cross the docker bridge, and a default-deny firewall
# silently DROPs that. Tor still publishes an address, so the service looks
# healthy while every visitor hangs. Test the real path instead of guessing.
use_host_net=0
if [ "$has_host" -eq 1 ]; then
  mapfile -t hports < <(host_ports)
  blocked=()
  echo
  echo "checking that a container can reach your host from here..."
  for hp in "${hports[@]}"; do
    reachable_from_container "$image" "$hp" || blocked+=("$hp")
  done

  if [ "${#blocked[@]}" -gt 0 ]; then
    echo
    echo "a container cannot reach port(s) ${blocked[*]} on this host."
    echo "usually a firewall dropping traffic from the docker bridge, or the app"
    echo "listening on 127.0.0.1 only. left as is, the .onion will just hang."
    echo
    if [ "${#nets[@]}" -eq 0 ]; then
      choose "How do you want to handle it?" \
        "Use the host network (no firewall change)" \
        "Keep the bridge, I will open the firewall" \
        "Continue anyway"
      case "$PICK" in
      "Use the host network (no firewall change)")
        use_host_net=1
        for i in "${!targets[@]}"; do
          case "${targets[$i]}" in
          *:host.docker.internal:*)
            vp="${targets[$i]%%:*}"
            tp="${targets[$i]##*:}"
            addr=127.0.0.1
            reachable_from_host 127.0.0.1 "$tp" || addr=172.17.0.1
            targets[$i]="$vp:$addr:$tp"
            ;;
          esac
        done
        ;;
      "Keep the bridge, I will open the firewall")
        echo
        for hp in "${blocked[@]}"; do echo "  $(firewall_hint "$hp")"; done
        echo
        echo "also make sure the app listens on 0.0.0.0 or 172.17.0.1, not 127.0.0.1."
        yesno "Continue writing the compose file?" y || die "aborted"
        ;;
      esac
    else
      echo "this setup also targets containers, so the host network is not an option."
      for hp in "${blocked[@]}"; do echo "  $(firewall_hint "$hp")"; done
      echo
      yesno "Continue anyway?" y || die "aborted"
    fi
  else
    echo "ok, the host is reachable from a container."
  fi
fi

harden=0
yesno "Hardening (read-only rootfs, drop all caps)?" y && harden=1
ask "Output file" "docker-compose.onion.yml"
out="$ANS"
if [ -e "$out" ]; then yesno "$out exists. Overwrite?" n || die "aborted"; fi

target_str=$(
  IFS=,
  echo "${targets[*]}"
)

{
  echo "services:"
  echo "  onion:"
  echo "    image: $image"
  echo "    restart: unless-stopped"
  echo "    environment:"
  echo "      TARGET: \"$target_str\""
  echo "    volumes:"
  echo "      - onion-keys:/var/lib/tor"
  if [ "$use_host_net" -eq 1 ]; then
    echo "    network_mode: host"
  else
    if [ "${#nets[@]}" -gt 0 ]; then
      echo "    networks:"
      for i in "${!nets[@]}"; do echo "      - net$((i + 1))"; done
    fi
    if [ "$has_host" -eq 1 ]; then
      echo "    extra_hosts:"
      echo '      - "host.docker.internal:host-gateway"'
    fi
  fi
  if [ "$harden" -eq 1 ]; then
    echo "    read_only: true"
    echo "    tmpfs:"
    echo "      - /tmp"
    echo "    cap_drop:"
    echo "      - ALL"
    echo "    security_opt:"
    echo "      - no-new-privileges:true"
  fi
  if [ "${#nets[@]}" -gt 0 ] && [ "$use_host_net" -eq 0 ]; then
    echo
    echo "networks:"
    for i in "${!nets[@]}"; do
      echo "  net$((i + 1)):"
      echo "    name: ${nets[$i]}"
      echo "    external: true"
    done
  fi
  echo
  echo "volumes:"
  echo "  onion-keys:"
} >"$out"

echo
echo "wrote $out  (TARGET=$target_str)"
echo

if docker compose version >/dev/null 2>&1; then
  DC="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  DC="docker-compose"
else DC=""; fi

manual() {
  echo "to start it later:"
  echo "  ${DC:-docker compose} -f $out up -d"
  echo "  ${DC:-docker compose} -f $out logs -f onion"
}

if [ -z "$DC" ]; then
  echo "docker compose not found."
  manual
  exit 0
fi
yesno "Start it now?" y || {
  manual
  exit 0
}

$DC -f "$out" up -d || die "compose up failed"

printf 'waiting for the onion address (Tor bootstrap, up to ~2 min)'
addr=""
for _ in $(seq 1 60); do
  addr=$($DC -f "$out" logs --no-color onion 2>&1 | sed -n 's/.*onion address: *//p' | head -n1 || true)
  [ -n "$addr" ] && break
  cid=$($DC -f "$out" ps -q onion 2>/dev/null || true)
  if [ -z "$cid" ] || [ "$(docker inspect -f '{{.State.Running}}' "$cid" 2>/dev/null || true)" != "true" ]; then
    echo
    echo "container stopped. last logs:"
    $DC -f "$out" logs --no-color --tail 20 onion || true
    exit 1
  fi
  printf '.'
  sleep 2
done
echo

if [ -z "$addr" ]; then
  echo "no onion address yet. check: $DC -f $out logs -f onion"
  exit 1
fi

echo
echo "onion is up:"
for t in "${targets[@]}"; do
  vp="${t%%:*}"
  rest="${t#*:}"
  if [ "$vp" = 80 ]; then url="http://$addr"; else url="http://$addr:$vp"; fi
  printf '  %s  ->  %s\n' "$url" "$rest"
done
echo
echo "open it in Tor Browser (can take another 30-60s while the descriptor publishes)."
echo
echo "logs:  $DC -f $out logs -f onion"
echo "stop:  $DC -f $out down      (key is kept; 'down -v' deletes the address forever)"
