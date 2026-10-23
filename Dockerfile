# webapp-security-orchestrator — self-contained audit environment.
#
# Bundles BOTH harnesses (Claude Code + pi), the claude-red skills, the
# orchestration agents, and the offensive tooling the web/api/auth/tls skills
# shell out to. Build once, then run the whole audit from inside the container.
#
#   docker build -t websec-orchestrator .
#   docker run -it \
#     --add-host=host.docker.internal:host-gateway \  # for pi -> local LLM
#     -v "$(pwd)/out:/home/analyst/webapp-security-orchestrator/out" \
#     websec-orchestrator
#
# The Claude Code harness prompts for credentials on first use; pi talks to the
# LLM you point pi/models.json at.
#
# Node 22 (Debian bookworm, glibc) covers both harnesses: Claude Code ships a
# glibc native binary via npm, and pi requires Node >= 22.19.
FROM node:22-bookworm-slim

# --- system packages the skills invoke directly ----------------------------
# openssl/nmap/sslscan: tls skill.  john: offline secret cracking (jwt skill).
# unzip: unpacks the tlsx binary.  nano: editing pi/models.json in-container.
# gosu: entrypoint drops root -> analyst after fixing the mounted out/ ownership.
# git/curl/ca-certificates: setup.sh clone + tool checkouts.  python venv: pip layer.
RUN apt-get update && apt-get install -y --no-install-recommends \
      bash git curl ca-certificates unzip nano gosu \
      openssl nmap sslscan john \
      python3 python3-venv python3-pip \
    && rm -rf /var/lib/apt/lists/*

# --- Python tooling, isolated in a venv kept on PATH for every user ---------
ENV VIRTUAL_ENV=/opt/venv
ENV PATH="$VIRTUAL_ENV/bin:$PATH"
RUN python3 -m venv "$VIRTUAL_ENV"
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

# --- testssl.sh (primary TLS auditor; bash + openssl, no other deps) --------
RUN git clone --depth 1 https://github.com/testssl/testssl.sh /opt/testssl.sh \
    && ln -s /opt/testssl.sh/testssl.sh /usr/local/bin/testssl.sh

# --- jwt_tool (auth/offensive-jwt); its deps are in the venv above ----------
RUN git clone --depth 1 https://github.com/ticarpi/jwt_tool /opt/jwt_tool \
    && printf '#!/bin/sh\nexec python3 /opt/jwt_tool/jwt_tool.py "$@"\n' > /usr/local/bin/jwt_tool \
    && chmod +x /usr/local/bin/jwt_tool

# --- tlsx (fast TLS probing); prebuilt release binary dropped on PATH -------
ARG TLSX_VERSION=1.4.0
RUN curl -fsSL -o /tmp/tlsx.zip \
      "https://github.com/projectdiscovery/tlsx/releases/download/v${TLSX_VERSION}/tlsx_${TLSX_VERSION}_linux_amd64.zip" \
    && unzip -o /tmp/tlsx.zip -d /tmp/tlsx \
    && install -m 0755 /tmp/tlsx/tlsx /usr/local/bin/tlsx \
    && rm -rf /tmp/tlsx /tmp/tlsx.zip

# --- harnesses --------------------------------------------------------------
# Claude Code: npm pulls the native binary (not run via Node).  pi: Node CLI.
RUN npm install -g @anthropic-ai/claude-code \
    && npm install -g --ignore-scripts @earendil-works/pi-coding-agent \
    && npm cache clean --force
# The global binary isn't writable by the non-root user, so skip the background
# updater (it would just fail noisily in an ephemeral container).
ENV DISABLE_AUTOUPDATER=1

# --- non-root user; render agents + fetch skills into the image -------------
# The workdir is created and owned by analyst before the USER switch: a directory
# materialised by WORKDIR is root-owned, which would stop setup.sh writing its
# config and out/ inside it.
# Reuse uid 1000 (the base image's `node` user) for analyst: it's the usual
# first-user uid on Linux, so bind-mounted reports come out host-owned by default
# with no invented uid. PUID/PGID (see the entrypoint) covers hosts where yours
# differs.
RUN userdel -r node 2>/dev/null || true \
    && useradd --create-home --uid 1000 --shell /bin/bash analyst \
    && mkdir -p /home/analyst/webapp-security-orchestrator \
    && chown -R analyst:analyst /home/analyst
# Pin HOME so it stays /home/analyst while the entrypoint runs as root and after
# gosu drops to analyst — Claude Code / pi keep creds and state there.
ENV HOME=/home/analyst
USER analyst
WORKDIR /home/analyst/webapp-security-orchestrator
COPY --chown=analyst:analyst . .

# setup.sh sparse-clones claude-red into ~/claude-red and renders the agents into
# ~/.claude/agents and ~/.pi/agent for both harnesses.
RUN ./setup.sh --harness both && ./setup.sh test

# Back to root so the entrypoint can chown the bind-mounted out/ before dropping
# to analyst via gosu. Claude Code prompts for creds on first use; pi's LLM
# endpoint is edited into pi/models.json, both at run time, not baked in.
USER root
ENTRYPOINT ["/home/analyst/webapp-security-orchestrator/docker-entrypoint.sh"]
CMD ["bash"]
