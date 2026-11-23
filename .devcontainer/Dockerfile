FROM public.ecr.aws/docker/library/node:24-bookworm-slim AS node
FROM public.ecr.aws/docker/library/rust:1-slim-bookworm AS rust
FROM public.ecr.aws/docker/library/docker:29-cli AS docker

FROM mcr.microsoft.com/devcontainers/base:1-noble
USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential cmake jq libssl-dev patch pkg-config python3 unzip \
    && rm -rf /var/lib/apt/lists/*

# act uses the Node executable in the runner image for JavaScript actions.
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=rust /usr/local/cargo/bin/rustup /usr/local/bin/rustup
RUN ln -s rustup /usr/local/bin/cargo \
    && ln -s rustup /usr/local/bin/rustc

COPY --from=docker /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker /usr/local/libexec/docker/cli-plugins/ /usr/local/libexec/docker/cli-plugins/
