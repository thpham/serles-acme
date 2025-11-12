# Docker Configuration Files

This directory contains Docker-specific configuration files for Serles ACME Server.

## Files

### Core Configuration

- **`gunicorn_config.py`** - Production Gunicorn server configuration

  - Workers: 4 (or 2\*CPU + 1)
  - Worker class: gevent (async I/O)
  - Timeout: 120s
  - Bind: 0.0.0.0:8080

- **`config.ini.template`** - Configuration template with environment variable support

  - Uses `${VAR:-default}` syntax
  - Processed by `entrypoint.sh` at container startup
  - Supports all Serles configuration options

- **`entrypoint.sh`** - Container initialization script
  - Environment variable substitution
  - Database readiness check
  - Database schema initialization
  - Configuration validation

### Bootstrap Scripts

- **`ejbca-bootstrap.sh`** - EJBCA development setup helper
  - Generates CSR for client certificate
  - Provides step-by-step Web UI configuration guide
  - Creates output directory for certificates

### Certificates (Runtime)

- **`certs/`** - Mount point for EJBCA client certificates
  - Place `client01-privpub.pem` here
  - PEM format (private key + certificate)
  - Mount as read-only in containers

## Quick Reference

### Using Configuration Template

The template supports environment variable substitution:

```bash
# Set environment variables
export DATABASE_URL="postgresql://user:pass@host:5432/db"
export EJBCA_API_URL="https://ejbca:8443/ejbca/ejbcaws/ejbcaws?wsdl"

# Start container (entrypoint.sh processes template)
docker-compose up -d
```

### Custom Configuration File

Override the entire config file:

```yaml
# docker-compose.yaml
volumes:
  - ./my-config.ini:/etc/serles/config.ini:ro
```

### Generate Client Certificate

```bash
# 1. Run bootstrap script
docker exec serles-ejbca /opt/ejbca-bootstrap.sh

# 2. Follow instructions to configure EJBCA

# 3. Copy certificate to docker/certs/
cp client01-privpub.pem docker/certs/

# 4. Restart Serles
docker-compose restart serles
```

## Environment Variables

See [README.docker.md](../README.docker.md#environment-variables) for complete list.

### Key Variables

| Variable            | Purpose             | Example                                         |
| ------------------- | ------------------- | ----------------------------------------------- |
| `DATABASE_URL`      | Database connection | `postgresql://user:pass@host/db`                |
| `EJBCA_API_URL`     | EJBCA SOAP endpoint | `https://ejbca:8443/ejbca/ejbcaws/ejbcaws?wsdl` |
| `EJBCA_CLIENT_CERT` | Client cert path    | `/etc/serles/client01-privpub.pem`              |
| `GUNICORN_WORKERS`  | Worker processes    | `4`                                             |
| `LOG_LEVEL`         | Logging level       | `info` / `debug`                                |

## Deployment Patterns

### Development (docker-compose)

Full stack with PostgreSQL and EJBCA:

```bash
cd /path/to/serles-acme
docker-compose up -d
```

### Production (standalone)

```bash
docker run -d \
  -p 8080:8080 \
  -e DATABASE_URL="postgresql://..." \
  -v ./certs:/etc/serles/certs:ro \
  ghcr.io/thpham/serles-acme:latest
```

### Kubernetes

```yaml
volumeMounts:
  - name: config
    mountPath: /etc/serles/config.ini
    subPath: config.ini
  - name: certs
    mountPath: /etc/serles/certs
    readOnly: true
```

## Troubleshooting

### Configuration Issues

```bash
# View processed config
docker-compose exec serles cat /etc/serles/config.ini

# Test environment variable substitution
docker-compose exec serles env | grep EJBCA
```

### Certificate Issues

```bash
# Verify certificate format
openssl x509 -in docker/certs/client01-privpub.pem -text -noout

# Check permissions
ls -la docker/certs/
```

### Gunicorn Issues

```bash
# View Gunicorn logs
docker-compose logs -f serles

# Adjust worker count
environment:
  GUNICORN_WORKERS: "2"
```

## See Also

- [README.docker.md](../README.docker.md) - Complete Docker deployment guide
- [../docs/ejbca-configuration.rst](../docs/ejbca-configuration.rst) - EJBCA configuration details
- [config.ini.example](../config.ini.example) - Configuration reference
