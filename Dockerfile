FROM node:20-slim
WORKDIR /tmp
RUN apt-get update && \
    apt-get upgrade -y --no-install-recommends && \
    apt-get install -y --no-install-recommends git && \
    rm -rf /var/lib/apt/lists/*
RUN npm install -g @anthropic-ai/claude-code
ARG USER_UID=1000
RUN usermod -u ${USER_UID} -l claudeuser -d /home/claudeuser -m node && \
    mkdir -p /home/claudeuser/.claude && \
    chown -R ${USER_UID}:${USER_UID} /home/claudeuser
USER claudeuser
WORKDIR /workspace
