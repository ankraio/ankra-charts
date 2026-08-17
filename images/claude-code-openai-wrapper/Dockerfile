# ghcr.io/ankraio/images/claude-code-openai-wrapper
#
# Upstream (github.com/RichardAtCT/claude-code-openai-wrapper) publishes no
# container image and its checked-in Dockerfile is a development setup: root,
# `--reload`, Poetry invoked at runtime, the whole build context copied in.
# This build turns the pinned upstream release into a production image:
# dependencies resolved from poetry.lock with hash verification, no build
# tooling in the runtime layer, a fixed non-root user, and uvicorn without
# --reload. The Claude Code CLI arrives bundled inside the claude-agent-sdk
# wheel (platform-specific, no Node.js needed).
#
# Upstream declares MIT in its pyproject.toml (`license = "MIT"`); it ships no
# LICENSE file.

FROM python:3.12-slim AS build

ARG UPSTREAM_REPOSITORY=https://github.com/RichardAtCT/claude-code-openai-wrapper
# v2.3.0 - the commit is what gets fetched; keep it and the tag in step.
ARG UPSTREAM_COMMIT=74951748c5085daa60c61e13db72a9ae1b81b208

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir /upstream \
    && curl -fsSL "${UPSTREAM_REPOSITORY}/archive/${UPSTREAM_COMMIT}.tar.gz" \
       | tar -xz --strip-components=1 -C /upstream

# poetry.lock is lock-version 2.1, written by Poetry 2.x; export needs the
# plugin there. --require-hashes makes pip refuse anything the lock did not
# pin.
RUN pip install --no-cache-dir "poetry==2.2.1" "poetry-plugin-export==1.9.0" \
    && cd /upstream \
    && poetry export --without dev --format requirements.txt --output /tmp/requirements.txt \
    && python -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir --require-hashes -r /tmp/requirements.txt

FROM python:3.12-slim

ARG UPSTREAM_COMMIT=74951748c5085daa60c61e13db72a9ae1b81b208
LABEL org.opencontainers.image.title="claude-code-openai-wrapper" \
      org.opencontainers.image.description="OpenAI API-compatible wrapper for Claude Code, built by Ankra from the pinned upstream release" \
      org.opencontainers.image.source="https://github.com/ankraio/ankra-charts" \
      org.opencontainers.image.url="https://github.com/ankraio/ankra-charts/tree/main/images/claude-code-openai-wrapper" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.revision="${UPSTREAM_COMMIT}" \
      org.opencontainers.image.vendor="Ankra AB"

RUN groupadd --gid 10001 wrapper \
    && useradd --uid 10001 --gid 10001 --home-dir /home/wrapper --create-home \
       --shell /usr/sbin/nologin wrapper

COPY --from=build /opt/venv /opt/venv
COPY --from=build /upstream/src /app/src
COPY --from=build /upstream/pyproject.toml /app/pyproject.toml

WORKDIR /app

# HOME must stay writable at runtime: the bundled Claude Code CLI keeps its
# state under ~/.claude. Under readOnlyRootFilesystem the chart mounts
# emptyDirs over /home/wrapper and /tmp.
ENV PATH="/opt/venv/bin:${PATH}" \
    PYTHONUNBUFFERED=1 \
    HOME=/home/wrapper \
    PORT=8000

EXPOSE 8000

USER 10001:10001

CMD ["/bin/sh", "-c", "exec uvicorn src.main:app --host ${CLAUDE_WRAPPER_HOST:-0.0.0.0} --port ${PORT:-8000}"]
