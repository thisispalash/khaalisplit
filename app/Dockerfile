FROM python:3.13-slim

WORKDIR /app

# Install Poetry + system deps
RUN apt-get update && apt-get install -y curl make && \
  curl -sSL https://install.python-poetry.org | python3 - && \
  apt-get clean && rm -rf /var/lib/apt/lists/*

ENV PATH="/root/.local/bin:$PATH"

# Download Tailwind CSS standalone CLI (detect arch for Apple Silicon / x64)
# Installed to /usr/local/bin so it survives bind mounts in dev
ARG TARGETARCH
RUN TWARCH=$([ "$TARGETARCH" = "arm64" ] && echo "arm64" || echo "x64") && \
  curl -sLO "https://github.com/tailwindlabs/tailwindcss/releases/latest/download/tailwindcss-linux-${TWARCH}" && \
  chmod +x "tailwindcss-linux-${TWARCH}" && mv "tailwindcss-linux-${TWARCH}" /usr/local/bin/tailwindcss

# Copy dependency mgmt for caching optimization
COPY pyproject.toml poetry.lock /app/
RUN poetry update

# Copy the rest of the project
COPY . /app

# Build production CSS
RUN tailwindcss -i static/css/tw-in.css -o static/css/tw.css --minify

CMD ["make", "prod"]
