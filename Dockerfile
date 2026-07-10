FROM docker.io/library/python:3.12.13-alpine3.23 AS checkov_builder

ARG CHECKOV_VERSION=3.3.1

RUN set -eux; \
    apk add --no-cache \
        libffi-dev=3.5.2-r0 \
        openssl-dev=3.5.7-r0 \
        build-base=0.5-r3

RUN set -eux; \
    python3 -m venv /opt/checkov-venv; \
    /opt/checkov-venv/bin/pip install --no-cache-dir --upgrade pip wheel setuptools; \
    /opt/checkov-venv/bin/pip install --no-cache-dir checkov=="${CHECKOV_VERSION}"

FROM docker.io/cytopia/ansible:2.20-tools@sha256:d3e18961b279acb7274af6a8413d7a9684c8f400679af55864e8b2ec3df5725a AS ansible

ARG PYTHON_VERSION=3.12.13-r0

SHELL ["/bin/ash", "-o", "pipefail", "-c"]

WORKDIR /tmp

RUN set -eux; \
    apk add --no-cache \
        wget=1.25.0-r2 \
        unzip=6.0-r16 \
        tar=1.35-r4 \
        curl=8.20.0-r0 \
        jq=1.8.1-r0 \
        c-ares=1.34.8-r0 \
        libcrypto3=3.5.7-r0 \
        libssl3=3.5.7-r0 \
        musl=1.2.5-r23 \
        zlib=1.3.2-r0

# ansible-lint
RUN set -eux; \
    apk add --no-cache \
        python3=${PYTHON_VERSION}; \
    /opt/venv/bin/pip install --no-cache-dir ansible-lint==26.6.0;

# molecule
RUN set -eux; \
    apk add --no-cache \
        python3=${PYTHON_VERSION} \
        rsync=3.4.3-r0 \
        docker-cli=29.5.2-r0; \
    /opt/venv/bin/pip install --no-cache-dir \
        molecule==26.6.0 \
        "molecule-plugins[docker]"==25.8.12; \
    ln -s /opt/venv/bin/molecule /usr/local/bin/molecule

# checov
COPY --from=checkov_builder /opt/checkov-venv /opt/checkov-venv
RUN set -eux; \
    apk add --no-cache \
        python3=${PYTHON_VERSION}; \
    ln -s /opt/checkov-venv/bin/checkov /usr/local/bin/checkov; \
    ln -s /usr/bin/python3 /usr/local/bin/python3

COPY ci/ /ci

RUN chmod +x /ci/entrypoint.sh

WORKDIR /source

HEALTHCHECK --interval=10s --timeout=2s --retries=3 \
  CMD which ansible-playbook ansible-lint checkov || exit 1

ENTRYPOINT ["/ci/entrypoint.sh"]