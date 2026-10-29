FROM mcr.microsoft.com/playwright:v1.64.1-noble

ARG CLAUDE_VERSION=2.1.312
ARG MCP_VERSION=0.0.83
ARG QA_UID=1001
ARG QA_GID=1001

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       ca-certificates curl git openssh-client python3 \
    && rm -rf /var/lib/apt/lists/*

RUN npm install --global \
      "@anthropic-ai/claude-code@${CLAUDE_VERSION}" \
      "@playwright/mcp@${MCP_VERSION}" \
    && npm cache clean --force

RUN set -eu; \
    browser="$(find /ms-playwright -type f -path '*/chrome-linux*/chrome' -print -quit)"; \
    test -n "$browser"; \
    ln -s "$browser" /usr/local/bin/qa-chromium

RUN set -eu; \
    test "${QA_UID}" -gt 0; \
    test "${QA_GID}" -gt 0; \
    if getent group "${QA_GID}" >/dev/null; then \
        existing_group="$(getent group "${QA_GID}" | cut -d: -f1)"; \
        if [ "$existing_group" != qa ]; then groupmod --new-name qa "$existing_group"; fi; \
    else \
        groupadd --gid "${QA_GID}" qa; \
    fi; \
    if getent passwd "${QA_UID}" >/dev/null; then \
        existing_user="$(getent passwd "${QA_UID}" | cut -d: -f1)"; \
        usermod --login qa --home /home/qa --move-home --gid qa --shell /bin/bash "$existing_user"; \
    else \
        useradd --uid "${QA_UID}" --gid qa --create-home --shell /bin/bash qa; \
    fi; \
    install -d -o qa -g qa /work/repo /home/qa/.claude/agents

COPY --chown=qa:qa agents/qa-lead.md agents/qa-runner.md agents/qa-api.md /home/qa/.claude/agents/
COPY --chown=qa:qa agents/qa-web-server.md /home/qa/.claude/agents/qa-web.md
COPY --chmod=755 docker/entrypoint.sh /usr/local/bin/qa-entrypoint

ENV HOME=/home/qa
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright

USER qa
WORKDIR /work/repo

ENTRYPOINT ["/usr/local/bin/qa-entrypoint"]
CMD ["claude"]
