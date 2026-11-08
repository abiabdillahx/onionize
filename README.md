# onionize

Expose any Docker service as a Tor onion service with one env var.

No `torrc` to write, no host ports to publish. Drop it next to your app in `docker-compose.yml`, set `TARGET`, and read the `.onion` address from the logs.

## Quick start

```yaml
services:
  app:
    image: nginx:alpine

  onion:
    image: ghcr.io/abiabdillahx/onionize
    restart: unless-stopped
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

Or with plain `docker run` on a shared network:

```sh
docker run -d --name onion --network mynet \
  -e TARGET=app:80 -v onion-keys:/var/lib/tor \
  ghcr.io/abiabdillahx/onionize
```

A hardened example (read-only rootfs, dropped caps) is in `docker-compose.example.yml`.

## Configuration

| Var | Default | Description |
|---|---|---|
| `TARGET` | required | `host:port` (served on onion port 80) or `onionport:host:port`. Comma-separate for multiple services |
| `WAIT_TIMEOUT` | `30` | Seconds to wait for the target hostname to resolve |
| `HS_DIR` | `/var/lib/tor/hidden_service` | Hidden service directory. Rarely needs changing |

Examples:

```
TARGET=app:3000                 # http://xxxx.onion      -> app:3000
TARGET=app:3000,443:app:3443    # port 80 -> app:3000, port 443 -> app:3443
TARGET=web:80,22:ssh:22         # two different services, one .onion
```

## Notes

- **Persist `/var/lib/tor`.** The onion private key lives there. Lose the volume and the `.onion` address is gone for good. Back it up, never commit it.
- **No `ports:` needed** on the app, so no host port conflicts.
- **Hostname is resolved once at startup** (Tor behavior). If the app container is recreated with a new IP, run `docker compose restart onion`.
- **An onion service is not an anonymous app.** Check that the app doesn't leak identity: absolute URLs to your clearnet domain, external fonts/CDNs, verbose `Server` / `X-Powered-By` headers, error pages that print hostnames.
- Client + hidden service only (`SocksPort 0`). Not meant as a relay or exit node.
- Need a general Tor image (SOCKS proxy, relay, bridge)? See [dockurr/tor](https://hub.docker.com/r/dockurr/tor). Onionize is the narrow case: service in, `.onion` out.

## Build from source

```sh
git clone git@github.com:abiabdillahx/onionize.git
cd onionize
docker build -t onionize .
```

## Release

Pushing a version tag builds and publishes a multi-arch image (`amd64`, `arm64`) to GHCR:

```sh
git tag v0.1.0 && git push --tags
```

After the first publish, set the package to **Public** in GitHub → Packages → onionize → Package settings, otherwise `docker pull` fails with `unauthorized`.
