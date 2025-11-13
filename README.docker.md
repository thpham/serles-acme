# Serles ACME Server - Docker Deployment Guide

Complete guide for running Serles ACME Server with Docker and Docker Compose, including EJBCA CE PKI integration.

---

## Table of Contents

- [Quick Start](#quick-start)
- [Architecture Overview](#architecture-overview)
- [Configuration](#configuration)
- [Development Setup](#development-setup)
- [Production Deployment](#production-deployment)
- [Kubernetes Deployment](#kubernetes-deployment)
- [Troubleshooting](#troubleshooting)
- [Advanced Topics](#advanced-topics)

---

## Quick Start

### Prerequisites

- Docker 24.0+ with BuildKit support
- Docker Compose 2.0+
- 4GB RAM minimum (for full stack with EJBCA)
- Multi-architecture support: amd64, arm64

### 1. Clone and Start

```bash
# Clone repository
git clone https://github.com/thpham/serles-acme.git
cd serles-acme

# Start full stack (Serles + PostgreSQL + EJBCA)
docker-compose up -d

# Check status
docker-compose ps
```

**Note for Apple Silicon (Mx chip) Users:**

EJBCA CE only provides AMD64 images, but Docker Desktop will automatically use Rosetta 2 emulation. The `platform: linux/amd64` is already configured in [docker-compose.yaml](docker-compose.yaml:37). Expect slightly slower startup times (~3-4 minutes for EJBCA instead of ~2 minutes).

### 2. Configure EJBCA (First Time Only - Automated)

```bash
# Wait for EJBCA to be healthy (takes ~2-3 minutes)
docker-compose logs -f ejbca
# Press Ctrl+C when you see "INFO: Server startup completed"

# Run fully automated bootstrap script
./docker/run-ejbca-bootstrap.sh

# This script will automatically:
#   1. Create ACME Certificate Authority (ACMECA)
#   2. Generate client certificate for Serles SOAP API access (P12 format)
#   3. Configure administrator role and permissions
#   4. Export certificates to /mnt/persistent inside EJBCA container
#   5. Convert P12 certificate to PEM format using host's openssl
#   6. Copy certificates to ./docker/certs/ directory
#   7. Set proper file permissions (600)
#   8. Restart Serles container to pick up the certificate
#   9. Display verification logs

# IMPORTANT: Restart EJBCA to apply configuration changes
docker-compose restart ejbca

# Wait for EJBCA to be healthy again (~2 minutes)
docker-compose logs -f ejbca
# Press Ctrl+C when you see "INFO: Server startup completed"
```

**Alternative: Manual Configuration**

If you prefer manual configuration or need custom profiles:

```bash
# Access EJBCA Web UI
# URL: https://localhost:9443/ejbca/
# Follow instructions in docker/ejbca-bootstrap.sh comments
```

### 3. Verify Serles

```bash
# Check health
curl http://localhost:8080/

# Check ACME directory
curl http://localhost:8080/directory
```

### 4. Try the Demo (Optional)

See Serles in action with automatic HTTPS via Caddy:

```bash
# One command - Caddy automatically gets certificate!
docker-compose -f docker-compose.demo.yml up -d

# Access demo site
open https://localhost:8043
```

For details, see [README.demo.md](README.demo.md).

---

## Architecture Overview

### Components

```
┌─────────────────────────────────────────────────────────────┐
│                     Docker Compose Stack                     │
├─────────────────┬────────────────────┬─────────────────────┤
│  Serles ACME    │  PostgreSQL 17     │  EJBCA CE (latest)  │
│  Port: 8080     │  Port: 5432        │  Port: 9443         │
│  Python 3.12    │  Database          │  PKI Backend        │
│  Gunicorn+gevent│  Persistent Volume │  TLS Enabled        │
└─────────────────┴────────────────────┴─────────────────────┘
          ↓                ↓                      ↓
    serles-network (Bridge Network)
```

### Image Details

**Serles ACME:**

- **Base**: `python:3.12-slim` (multi-stage build)
- **Size**: ~468MB
- **Platforms**: `linux/amd64`, `linux/arm64`
- **Registry**: `ghcr.io/thpham/serles-acme`
- **Tags**:
  - `latest` - Latest stable release
  - `v{version}` - Semantic version (e.g., v1.2.0)
  - `version-{sha}` - Development builds from master

**EJBCA CE:**

- **Platform**: `linux/amd64` only (uses Rosetta 2 emulation on Apple Silicon)
- **Note**: Expect 50% slower startup on ARM64 hosts (~3-4 minutes vs ~2 minutes)

---

## Configuration

### Environment Variables

| Variable                   | Description                     | Default                                             |
| -------------------------- | ------------------------------- | --------------------------------------------------- |
| `DATABASE_URL`             | PostgreSQL connection string    | `sqlite:////var/lib/serles/db.sqlite`               |
| `BACKEND`                  | Backend module                  | `serles.backends.ejbca:EjbcaBackend`                |
| `EJBCA_API_URL`            | EJBCA SOAP endpoint             | `https://localhost:9443/ejbca/ejbcaws/ejbcaws?wsdl` |
| `EJBCA_CA_BUNDLE`          | CA certificate verification     | `none`                                              |
| `EJBCA_CLIENT_CERT`        | Client certificate path         | `/etc/serles/client01-privpub.pem`                  |
| `EJBCA_CA_NAME`            | CA name in EJBCA                | `ACMECA`                                            |
| `EJBCA_END_ENTITY_PROFILE` | End entity profile              | `ACMEEndEntityProfile`                              |
| `EJBCA_CERT_PROFILE`       | Certificate profile             | `ACMEServerProfile`                                 |
| `SUBJECT_NAME_TEMPLATE`    | Subject DN template             | `CN={SAN[0]}`                                       |
| `FORCE_TEMPLATE_DN`        | Override CSR DN                 | `true`                                              |
| `ALLOW_WILDCARDS`          | Allow `*.example.com` certs     | `false`                                             |
| `VERIFY_PTR`               | Verify reverse DNS              | `false`                                             |
| `ALLOWED_IP_RANGES`        | CIDR ranges (newline-separated) | ` ` (all allowed)                                   |
| `EXCLUDED_IP_RANGES`       | Excluded CIDR ranges            | ` `                                                 |
| `GUNICORN_WORKERS`         | Number of workers               | `4`                                                 |
| `LOG_LEVEL`                | Log level                       | `info`                                              |

### Configuration Modes

#### 1. Environment Variables (Recommended for Docker/K8s)

```yaml
services:
  serles:
    environment:
      DATABASE_URL: "postgresql://user:pass@host:5432/db"
      EJBCA_API_URL: "https://ejbca:8443/ejbca/ejbcaws/ejbcaws?wsdl" # EJBCA internal port
      ALLOW_WILDCARDS: "true"
```

#### 2. Configuration File Override

```yaml
services:
  serles:
    volumes:
      - ./my-config.ini:/etc/serles/config.ini:ro
```

#### 3. Hybrid Approach (Both)

Environment variables take precedence over file values via template substitution.

---

## Development Setup

### Full Stack with Docker Compose

```bash
# Start all services
docker-compose up -d

# View logs
docker-compose logs -f serles

# Stop all services
docker-compose down

# Clean up (including volumes)
docker-compose down -v
```

### EJBCA Configuration

After starting EJBCA for the first time, configure it for Serles:

```bash
# 1. Run bootstrap script
docker exec serles-ejbca /opt/ejbca-bootstrap.sh

# 2. Access EJBCA Web UI
open https://localhost:9443/ejbca/

# 3. Complete configuration steps (see bootstrap output)
#    - Create CA (ACMECA)
#    - Create Certificate Profiles
#    - Create End Entity Profiles
#    - Create API user and role
#    - Issue client certificate

# 4. Copy CSR content from bootstrap output
docker exec serles-ejbca cat /tmp/serles-certs/client01.csr

# 5. Issue certificate via EJBCA Web UI

# 6. Combine certificate and key
cat client01.key client01.pem > client01-privpub.pem

# 7. Mount certificate for Serles
mkdir -p docker/certs
cp client01-privpub.pem docker/certs/

# 8. Update docker-compose.yaml volume mount
# volumes:
#   - ./docker/certs/client01-privpub.pem:/etc/serles/client01-privpub.pem:ro

# 9. Restart Serles
docker-compose restart serles
```

### Testing with OpenSSL Backend

For quick testing without EJBCA:

```bash
# Override backend in docker-compose.yaml
environment:
  BACKEND: "serles.backends.openssl:OpenSSLBackend"
  # Remove EJBCA-specific variables

# Start only Serles and PostgreSQL
docker-compose up -d serles postgresql
```

---

## Production Deployment

### Standalone Docker

```bash
# Pull image
docker pull ghcr.io/thpham/serles-acme:latest

# Run with external PostgreSQL and EJBCA
docker run -d \
  --name serles-acme \
  -p 8080:8080 \
  -e DATABASE_URL="postgresql://user:pass@postgres.example.com:5432/serles" \
  -e EJBCA_API_URL="https://ejbca.example.com/ejbca/ejbcaws/ejbcaws?wsdl" \
  -e EJBCA_CA_BUNDLE="/etc/serles/ejbca-ca.pem" \
  -e EJBCA_CLIENT_CERT="/etc/serles/client01-privpub.pem" \
  -v /path/to/certs:/etc/serles/certs:ro \
  -v serles-data:/var/lib/serles \
  ghcr.io/thpham/serles-acme:latest
```

### TLS Termination

Serles runs HTTP internally. Use a reverse proxy for TLS:

#### Nginx Example

```nginx
upstream serles {
    server localhost:8080;
}

server {
    listen 443 ssl http2;
    server_name acme.example.com;

    ssl_certificate /etc/nginx/certs/server.crt;
    ssl_certificate_key /etc/nginx/certs/server.key;

    location / {
        proxy_pass http://serles;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

#### Traefik Example

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.serles.rule=Host(`acme.example.com`)"
  - "traefik.http.routers.serles.entrypoints=websecure"
  - "traefik.http.routers.serles.tls.certresolver=letsencrypt"
  - "traefik.http.services.serles.loadbalancer.server.port=8080"
```

---

## Kubernetes Deployment

### Example Manifests

#### ConfigMap

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: serles-config
data:
  config.ini: |
    [serles]
    database = postgresql://serles:password@postgresql:5432/serles
    backend = serles.backends.ejbca:EjbcaBackend
    # ... (rest of config)
```

#### Secret (Client Certificate)

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: serles-ejbca-cert
type: Opaque
data:
  client01-privpub.pem: <base64-encoded-cert>
```

#### Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: serles-acme
spec:
  replicas: 3
  selector:
    matchLabels:
      app: serles-acme
  template:
    metadata:
      labels:
        app: serles-acme
    spec:
      containers:
        - name: serles
          image: ghcr.io/thpham/serles-acme:latest
          ports:
            - containerPort: 8080
              name: http
          env:
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: serles-db-secret
                  key: connection-string
            - name: EJBCA_API_URL
              value: "https://ejbca.example.com/ejbca/ejbcaws/ejbcaws?wsdl"
          volumeMounts:
            - name: config
              mountPath: /etc/serles/config.ini
              subPath: config.ini
            - name: certs
              mountPath: /etc/serles/certs
              readOnly: true
          livenessProbe:
            httpGet:
              path: /
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /directory
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 5
      volumes:
        - name: config
          configMap:
            name: serles-config
        - name: certs
          secret:
            secretName: serles-ejbca-cert
```

#### Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: serles-acme
spec:
  selector:
    app: serles-acme
  ports:
    - port: 80
      targetPort: 8080
      name: http
  type: ClusterIP
```

#### Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: serles-ingress
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  tls:
    - hosts:
        - acme.example.com
      secretName: serles-tls
  rules:
    - host: acme.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: serles-acme
                port:
                  number: 80
```

---

## Troubleshooting

### Common Issues

#### 1. EJBCA Connection Failed

**Symptoms**: `zeep.exceptions.TransportError` or `SSL: CERTIFICATE_VERIFY_FAILED`

**Solutions**:

```bash
# Check EJBCA is accessible
curl -k https://ejbca:8443/ejbca/publicweb/healthcheck/ejbcahealth

# Verify client certificate
openssl x509 -in client01-privpub.pem -text -noout

# Disable certificate verification for testing
environment:
  EJBCA_CA_BUNDLE: "none"
```

#### 2. Database Connection Timeout

**Symptoms**: `psycopg2.OperationalError: could not connect to server`

**Solutions**:

```bash
# Check PostgreSQL is ready
docker-compose logs postgresql

# Verify connection string
docker-compose exec serles env | grep DATABASE_URL

# Test connection manually
docker-compose exec serles pg_isready -h postgresql -p 5432
```

#### 3. Gunicorn Worker Timeout

**Symptoms**: `[CRITICAL] WORKER TIMEOUT`

**Solutions**:

```bash
# Increase timeout in docker/gunicorn_config.py
timeout = 180  # seconds

# Reduce workers if resource-constrained
environment:
  GUNICORN_WORKERS: "2"
```

#### 4. Permission Denied

**Symptoms**: `PermissionError: [Errno 13] Permission denied`

**Solutions**:

```bash
# Check file ownership
docker-compose exec serles ls -la /etc/serles/

# Ensure volumes are writable
docker-compose exec serles touch /var/lib/serles/test.txt
```

### Debug Mode

```bash
# Enable debug logging
environment:
  LOG_LEVEL: "debug"

# View real-time logs
docker-compose logs -f serles

# Exec into container
docker-compose exec serles bash

# Check config
docker-compose exec serles cat /etc/serles/config.ini

# Test connectivity
curl http://localhost:8080/directory
```

---

## Advanced Topics

### Custom Backends

Create a custom backend by extending `serles.backends.base.Backend`:

```python
# custom_backend.py
from serles.backends.base import Backend

class CustomBackend(Backend):
    def issue_certificate(self, csr, subject_alt_names):
        # Your implementation
        pass
```

Mount in container:

```yaml
volumes:
  - ./custom_backend.py:/app/custom_backend.py:ro
environment:
  BACKEND: "custom_backend:CustomBackend"
```

### Performance Tuning

```bash
# Increase workers for high load
GUNICORN_WORKERS: "8"  # 2 * CPU_cores + 1

# Use gevent for I/O-bound workloads (default)
# worker_class = "gevent" in gunicorn_config.py

# Connection pooling for PostgreSQL
DATABASE_URL: "postgresql://user:pass@host:5432/db?pool_size=20&max_overflow=10"
```

### Monitoring

```yaml
# Prometheus metrics (if integrated)
- name: metrics
  containerPort: 9090

# Health check endpoint
curl http://localhost:8080/
```

### Security Hardening

```bash
# 1. Use secrets management
docker secret create ejbca_cert client01-privpub.pem

# 2. Network isolation
networks:
  frontend:
    external: true
  backend:
    internal: true

# 3. Read-only root filesystem
security_opt:
  - no-new-privileges:true
read_only: true
tmpfs:
  - /tmp
```

---

## CI/CD Integration

### GitHub Actions (Included)

The repository includes `.github/workflows/docker-build.yml`:

- **Triggers**: Push to master, Git tags, Manual dispatch
- **Builds**: Multi-arch (amd64, arm64)
- **Registry**: GitHub Container Registry (GHCR)
- **Tagging**:
  - `v{version}` → `{version}` + `latest`
  - Push to master → `version-{short_sha}`
  - Cleanup: Keep last 4 `version-*` tags

### Building Locally

```bash
# Build for current architecture
docker build -t serles-acme:local .

# Multi-arch build
docker buildx create --use
docker buildx build --platform linux/amd64,linux/arm64 -t serles-acme:multi .
```

---

## Support

- **Issues**: https://github.com/thpham/serles-acme/issues
- **Original Project**: https://github.com/dvtirol/serles-acme
- **EJBCA Docs**: https://www.primekey.com/products/ejbca-enterprise/

---

## License

GNU General Public License v3 (GPLv3)
