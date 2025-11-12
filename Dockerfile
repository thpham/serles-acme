# Multi-stage Dockerfile for Serles ACME Server
# Optimized for minimal size and production deployment
# Supports: amd64, arm64

# ============================================================================
# Stage 1: Builder - Install dependencies and build application
# ============================================================================
FROM python:3.12-slim AS builder

# Set working directory
WORKDIR /build

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    g++ \
    libpq-dev \
    libffi-dev \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements files
COPY setup.py README.rst ./
COPY serles/ ./serles/
COPY bin/ ./bin/

# Install Python dependencies including gevent for async workers
# psycopg2-binary for PostgreSQL support
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir \
    gevent \
    psycopg2-binary \
    && pip install --no-cache-dir .

# ============================================================================
# Stage 2: Runtime - Minimal production image
# ============================================================================
FROM python:3.12-slim

LABEL maintainer="thpham"
LABEL description="Serles ACME Server with EJBCA CE PKI integration"
LABEL org.opencontainers.image.source="https://github.com/thpham/serles-acme"

# Install runtime dependencies only
RUN apt-get update && apt-get install -y --no-install-recommends \
    openssl \
    libpq5 \
    curl \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user for security
RUN groupadd -r serles --gid=1000 && \
    useradd -r -g serles --uid=1000 --home-dir=/app --shell=/bin/bash serles

# Create directory structure
RUN mkdir -p /etc/serles /var/lib/serles /app && \
    chown -R serles:serles /etc/serles /var/lib/serles /app

# Copy Python packages from builder
COPY --from=builder /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin

# Set working directory
WORKDIR /app

# Copy application code
COPY --chown=serles:serles serles/ ./serles/
COPY --chown=serles:serles bin/ ./bin/
COPY --chown=serles:serles setup.py README.rst ./

# Copy Docker-specific files
COPY --chown=serles:serles docker/gunicorn_config.py /etc/serles/gunicorn_config.py
COPY --chown=serles:serles docker/config.ini.template /etc/serles/config.ini.template
COPY --chown=serles:serles docker/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --chown=serles:serles config.ini.example /etc/serles/config.ini.example

# Make scripts executable
RUN chmod +x /usr/local/bin/serles /usr/local/bin/entrypoint.sh

# Install the package in the runtime environment
RUN pip install --no-cache-dir -e .

# Switch to non-root user
USER serles

# Set environment variables
ENV CONFIG=/etc/serles/config.ini \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# Expose port (HTTP - TLS terminates at ingress)
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:8080/ || exit 1

# Entrypoint
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# Default command (can be overridden)
CMD ["/usr/local/bin/serles"]
