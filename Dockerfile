FROM alpine:3.20

RUN apk add --no-cache tor \
 && mkdir -p /var/lib/tor \
 && chown -R tor:tor /var/lib/tor \
 && chmod 700 /var/lib/tor

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER tor
VOLUME /var/lib/tor

HEALTHCHECK --interval=30s --timeout=3s --start-period=60s \
  CMD test -s /var/lib/tor/hidden_service/hostname || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
