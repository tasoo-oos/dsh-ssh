# Deployment image: dsh (npm pin) + this repository's beta branch + a baked web
# profile. Host-specific configuration is NOT baked in: it is mounted at
# /etc/dsh/overlay/web.yml and applied with `dsh --patch` by the entrypoint.
#
# Build:  docker build --build-arg DSH_SSH_REF=beta -t dsh:beta .
# Probe:  docker exec <ctr> dsh --profile web --dump-config | grep ssh-remote
ARG NODE_IMAGE=node:24-bookworm-slim@sha256:934240a162082fd8b8a2f90cd5114446443f1eba1c5378f6687167ca405e6584

FROM ${NODE_IMAGE} AS plugin
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates git \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /src
ARG DSH_SSH_REPO=https://github.com/tasoo-oos/dsh-ssh.git
ARG DSH_SSH_REF=beta
RUN git clone --depth 1 --branch "${DSH_SSH_REF}" "${DSH_SSH_REPO}" /src \
 && git rev-parse HEAD > /src/.built-from
RUN mkdir -p /out \
 && npm ci --no-audit --no-fund \
 && npm run build \
 && npx tsc --noEmit \
 && npm pack --pack-destination /out

FROM ${NODE_IMAGE} AS runtime
ARG NODE_IMAGE
ARG DSH_VERSION=0.2.1-rc.2
ARG PNPM_VERSION=11.22.0
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl git openssh-client ripgrep procps \
 && rm -rf /var/lib/apt/lists/*
RUN npm install -g "@deepseek-ai/dsh@${DSH_VERSION}" "pnpm@${PNPM_VERSION}" \
 && dsh --version
COPY --from=plugin /out/dsh-ssh-*.tgz /opt/dsh/pkgs/
COPY --from=plugin /src/.built-from /opt/dsh/dsh-ssh.rev
# Bake the web profile so the runtime needs no package manager or network.
# pnpm 11 refuses to install native deps whose build scripts are not approved;
# ssh2, cpu-features and koffi all ship prebuilt binaries, so deny the builds
# explicitly (same policy as the previous hand-managed profile).
ENV DSH_HOME=/opt/dsh
RUN dsh --profile web --dump-config > /dev/null \
 && printf 'allowBuilds:\n  cpu-features: false\n  koffi: false\n  ssh2: false\n' \
      >> /opt/dsh/profiles/web/pnpm-workspace.yaml \
 && dsh plugin --profile web add /opt/dsh/pkgs/dsh-ssh-*.tgz
RUN printf 'dsh=%s\ndsh-ssh=%s\nbase=%s\n' \
      "${DSH_VERSION}" "$(cat /opt/dsh/dsh-ssh.rev)" "${NODE_IMAGE}" \
      > /etc/dsh-build.json
COPY docker/entrypoint.sh /usr/local/bin/dsh-entrypoint
RUN chmod 0755 /usr/local/bin/dsh-entrypoint
ENV DSH_HOME=/data/dsh \
    HOME=/home/node \
    NODE_OPTIONS=--max-old-space-size=2048
USER node
WORKDIR /home/node
EXPOSE 3080
ENTRYPOINT ["/usr/local/bin/dsh-entrypoint"]
