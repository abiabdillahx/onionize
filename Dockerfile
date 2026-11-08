FROM alpine:3.20

# Pinned on purpose: the onion address is tied to this image's behaviour, so
# version drift should be an explicit bump, not a silent rebuild difference.
# To bump: docker run --rm alpine:3.20 sh -c 'apk update -q && apk policy tor'
ARG TOR_VERSION=0.4.9.11-r0

LABEL org.opencontainers.image.source="https://github.com/abiabdillahx/onionize" \
      org.opencontainers.image.description="Expose any Docker service as a Tor onion service with one env var" \
      org.opencontainers.image.licenses="MIT"

RUN apk add --no-cache "tor=${TOR_VERSION}" \
 && mkdir -p /var/lib/tor \
 && chown -R tor:tor /var/lib/tor \
 && chmod 700 /var/lib/tor

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER tor
VOLUME /var/lib/tor

# Tor bootstrap + descriptor publish regularly takes 90s+ on a slow network.
HEALTHCHECK --interval=30s --timeout=3s --start-period=120s \
  CMD test -s /var/lib/tor/hidden_service/hostname || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
