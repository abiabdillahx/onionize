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

## Interactive setup

Don't want to write the YAML by hand? Run:

```sh
./run.sh
```

It asks whether your service runs in Docker or directly on the host, lists your Docker networks and running containers to pick from, detects the container port, writes `docker-compose.onion.yml`, starts it, and prints the `.onion` address once Tor is ready. Repeat the prompt to put several services behind one `.onion`.

Requires `bash` and a running Docker daemon. Set `NO_COLOR=1` for a plain banner.

## Configuration

| Var | Default | Description |
|---|---|---|
| `TARGET` | required | `host:port` (served on onion port 80) or `onionport:host:port`. Comma-separate for multiple services. Hostname or IPv4 only, no IPv6, and each onion port may appear once |
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
- **Never share the key or the address carelessly.** `hs_ed25519_secret_key` *is* your service identity — anyone holding it can impersonate your `.onion`. When pasting logs into an issue, redact the address as `xxxx.onion`; an unlisted service stays unlisted only until it leaks.
- **No `ports:` needed** on the app, so no host port conflicts.
- **Hostname is resolved once at startup** (Tor behavior). If the app container is recreated with a new IP, run `docker compose restart onion`.
- **An onion service is not an anonymous app.** Check that the app doesn't leak identity: absolute URLs to your clearnet domain, external fonts/CDNs, verbose `Server` / `X-Powered-By` headers, error pages that print hostnames.
- Client + hidden service only (`SocksPort 0`). Not meant as a relay or exit node.
- **IPv4 only.** Targets are resolved with `getent ahostsv4`; a literal IPv6 address in `TARGET` is not supported (the `host:port` parser splits on `:`).
- Need a general Tor image (SOCKS proxy, relay, bridge)? See [dockurr/tor](https://hub.docker.com/r/dockurr/tor). Onionize is the narrow case: service in, `.onion` out.

## License

MIT (see `LICENSE`) — applies to this repository's source.

The published container image also bundles third-party software under its own licenses, including Tor (BSD-3-Clause AND GPL-3.0-only) and Alpine base packages (GPL-2.0, LGPL-2.1, Apache-2.0, MIT). Sources for those are available from the Alpine package mirrors. Onionize is not affiliated with, nor endorsed by, The Tor Project.

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
