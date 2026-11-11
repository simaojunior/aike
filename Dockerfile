ARG ELIXIR_IMAGE=docker.io/hexpm/elixir:1.20.0-erlang-29.0.1-debian-trixie-20260518-slim
ARG RUNTIME_IMAGE=docker.io/library/debian:trixie-20260518-slim

FROM ${ELIXIR_IMAGE} AS build
ARG RELEASE
RUN test -n "$RELEASE" || (echo "Set --build-arg RELEASE=<document_ocr|document_classifier|biometrics|backoffice>" && exit 1)
RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential git ca-certificates \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
ENV MIX_ENV=prod
RUN mix local.hex --force && mix local.rebar --force
COPY mix.exs mix.lock ./
COPY config config
COPY apps apps
RUN mix deps.get --only prod \
 && mix compile \
 && mix release "$RELEASE"

FROM ${RUNTIME_IMAGE}
ARG RELEASE
RUN set -eux; \
    vision=""; \
    case "$RELEASE" in \
      document_ocr|document_classifier) vision="tesseract-ocr tesseract-ocr-por poppler-utils" ;; \
      biometrics) vision="poppler-utils" ;; \
    esac; \
    apt-get update; \
    apt-get install -y --no-install-recommends libstdc++6 libncurses6 openssl ca-certificates curl $vision; \
    rm -rf /var/lib/apt/lists/*; \
    useradd --system --create-home --home-dir /app aike
WORKDIR /app
COPY --from=build --chown=aike:aike /app/_build/prod/rel/${RELEASE} ./
COPY --chown=aike:aike scripts/migrate.exs scripts/migrate.exs
COPY scripts/fetch_face_models.sh /tmp/fetch_face_models.sh
RUN if [ "$RELEASE" = biometrics ]; then /tmp/fetch_face_models.sh /app/models; fi \
 && rm /tmp/fetch_face_models.sh \
 && ln -s "/app/bin/${RELEASE}" /app/bin/server
USER aike
ENV LANG=C.UTF-8 \
    PHX_SERVER=true \
    AIKE_HTTP_IP=0.0.0.0 \
    PORT=4000 \
    CLASSIFIER_PORT=4000 \
    BIOMETRICS_PORT=4000 \
    BACKOFFICE_PORT=4000 \
    AIKE_FACE_MODELS_DIR=/app/models
EXPOSE 4000
HEALTHCHECK --interval=10s --timeout=3s --start-period=20s --retries=3 \
  CMD curl -fsS http://127.0.0.1:4000/health || exit 1
CMD ["/app/bin/server", "start"]
