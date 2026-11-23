FROM public.ecr.aws/docker/library/node:24-bookworm-slim AS node
FROM public.ecr.aws/docker/library/rust:1-slim-bookworm AS rust
FROM public.ecr.aws/docker/library/docker:29-cli AS docker

FROM public.ecr.aws/docker/library/ubuntu:24.04

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bsdextrautils build-essential ca-certificates clang cmake curl git jq \
        libclang-dev libssl-dev openssh-client patch pkg-config python3 sudo unzip xz-utils \
    && rm -rf /var/lib/apt/lists/*

RUN printf 'ubuntu ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/ubuntu \
    && chmod 0440 /etc/sudoers.d/ubuntu

# act uses the Node executable in the runner image for JavaScript actions.
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=rust /usr/local/cargo/bin/rustup /usr/local/bin/rustup
RUN ln -s rustup /usr/local/bin/cargo \
    && ln -s rustup /usr/local/bin/rustc

COPY --from=docker /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker /usr/local/libexec/docker/cli-plugins/ /usr/local/libexec/docker/cli-plugins/
