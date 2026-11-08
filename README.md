# tor-starter

Expose any Docker service as a Tor onion service with one env var.

## Usage

```yaml
services:
  app:
    image: nginx:alpine
  onion:
    image: ghcr.io/<you>/tor-starter
    depends_on: [app]
    environment:
      TARGET: app:80
    volumes:
      - onion-keys:/var/lib/tor
volumes:
  onion-keys:
```

```sh
docker compose up -d
docker compose logs onion   # -> onion address: xxxx.onion
```

See `docker-compose.example.yml` for a hardened version.

## Env vars

| Var | Default | Notes |
|---|---|---|
| `TARGET` | required | `host:port` (onion port 80) or `onionport:host:port`. Comma-separate for multiple, e.g. `app:3000,443:app:3443` |
| `WAIT_TIMEOUT` | `30` | Seconds to wait for the target hostname to resolve |
| `HS_DIR` | `/var/lib/tor/hidden_service` | Rarely needs changing |

## Notes

- **Persist `/var/lib/tor`.** The private key lives there. Lose the volume, lose the `.onion` address. Back it up, never commit it.
- No `ports:` needed on the app, so no host port conflicts.
- The target hostname is resolved once at startup. If the app container is recreated with a new IP, restart the onion container (`docker compose restart onion`).
- Onion service != anonymous app. Make sure the app doesn't leak identity: absolute URLs to your clearnet domain, external fonts/CDNs, verbose `Server`/`X-Powered-By` headers, error pages with hostnames.
- Don't run this as a public relay/exit. It's client + hidden service only (`SocksPort 0`).

## Build

```sh
docker build -t tor-starter .
```
