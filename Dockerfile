# Build Stage
FROM node:22-bookworm AS openclaw-build

# Install build dependencies
RUN apt-get update && apt-get install -y \
    git \
    ca-certificates \
    curl \
    python3 \
    make \
    g++ \
    && rm -rf /var/lib/apt/lists/*

# Install Bun
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

# Prepare Node/Bun environment
RUN corepack enable
WORKDIR /openclaw

# Clone Repository
ARG OPENCLAW_GIT_REF=main
RUN git clone --depth 1 --branch "${OPENCLAW_GIT_REF}" https://github.com/openclaw/openclaw.git .

# Patch package.json files
RUN set -eux; \
    find ./extensions -name 'package.json' -type f | while read -r f; do \
    sed -i -E 's/"openclaw"[[:space:]]*:[[:space:]]*">=[^"]+"/"openclaw": "*"/g' "$f"; \
    sed -i -E 's/"openclaw"[[:space:]]*:[[:space:]]*"workspace:[^"]+"/"openclaw": "*"/g' "$f"; \
    done

# Install & Build
RUN pnpm install --no-frozen-lockfile
RUN pnpm build

ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:install && pnpm ui:build

# ---
# Final Stage
# ---
FROM node:22-bookworm

ENV NODE_ENV=production

# Install system dependencies (including LibreOffice)
RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    build-essential \
    gcc \
    g++ \
    make \
    procps \
    file \
    git \
    python3 \
    python3-pip \
    python3-dev \
    wget \
    imagemagick \
    ghostscript \
    libreoffice \
    pkg-config \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
RUN pip3 install --break-system-packages \
    python-docx \
    openpyxl \
    pandas \
    numpy \
    requests \
    beautifulsoup4 \
    lxml \
    pillow

# Install Homebrew
RUN useradd -m -s /bin/bash linuxbrew && echo 'linuxbrew ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
USER linuxbrew
RUN NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Switch back to root
USER root
RUN chown -R root:root /home/linuxbrew/.linuxbrew
ENV PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH}"

# App Setup
WORKDIR /app
RUN corepack enable

COPY package.json pnpm-lock.yaml ./
RUN pnpm install --prod --frozen-lockfile && pnpm store prune

# Copy built artifacts from build stage
COPY --from=openclaw-build /openclaw /openclaw

# Create entrypoint script
RUN printf '%s\n' '#!/usr/bin/env bash' 'exec node /openclaw/dist/entry.js "$@"' > /usr/local/bin/openclaw \
    && chmod +x /usr/local/bin/openclaw

COPY src ./src

ENV PORT=8080
EXPOSE 8080

CMD ["node", "src/server.js"]
