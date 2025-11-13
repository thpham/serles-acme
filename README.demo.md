# Serles ACME Demo - Caddy Server

Minimal single-container demo showcasing automatic TLS certificate provisioning with:

- **Caddy** - Modern web server with built-in ACME support
- **Serles ACME Server** - Custom ACME endpoint
- **EJBCA CE** - PKI backend

## Why Caddy?

✅ **Zero Configuration** - Automatic HTTPS out of the box
✅ **Built-in ACME Client** - No need for Certbot or separate containers
✅ **Custom ACME Server** - Easily point to Serles instead of Let's Encrypt
✅ **Auto Renewal** - Handles certificate lifecycle automatically
✅ **One Container** - Simpler than nginx + certbot setup

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│                    Demo Stack                            │
│                                                          │
│  ┌────────────────────────────────────────┐              │
│  │          Caddy Container               │              │
│  │  ┌──────────────────────────────────┐  │              │
│  │  │ ncat proxy (background)          │  │              │
│  │  │ localhost:4000 -> serles:8080    │  │              │
│  │  └──────────────────────────────────┘  │              │
│  │  ┌──────────────────────────────────┐  │              │
│  │  │ Caddy Web Server                 │  │              │
│  │  │ - Ports: 80, 443                 │  │              │
│  │  │ - ACME client                    │  │              │
│  │  │ - ACME URL: http://127.0.0.1:4000│  │              │
│  │  └──────────────────────────────────┘  │              │
│  └────────────┬───────────────────────────┘              │
│               │                                          │
│               │ ACME Protocol via localhost proxy        │
└───────────────┼──────────────────────────────────────────┘
                │
                ▼
┌──────────────────────────────────────────────────────────┐
│            Serles ACME Server Stack                      │
│  (Running via docker-compose.yaml)                       │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  Serles:8080 ──▶ EJBCA:8443 ──▶ PostgreSQL:5432          │
│  (ACME Server)   (PKI Backend)  (Database)               │
│         │                                                │
│         │ HTTP-01 Challenge Validation                   │
│         └──────────▶ Caddy:80 (demo.serles.local)        │
│                     (via network alias)                  │
└──────────────────────────────────────────────────────────┘
```

**Key Technical Details**:

- **Network Alias**: Caddy has alias `demo.serles.local` for ACME challenge validation
- **ACME Proxy Workaround**: Caddy requires HTTPS for ACME servers, but we use HTTP Serles. The workaround runs `ncat` proxy inside Caddy container forwarding `localhost:4000` → `serles-acme:8080`. Caddy accepts `http://127.0.0.1:4000` as a valid "internal" ACME server.
- **Reference**: [Caddy Issue #1592](https://github.com/caddyserver/caddy/issues/1592)

## Prerequisites

### 1. Serles ACME Server

Ensure Serles ACME is running:

```bash
# Start main stack
docker-compose up -d

# Configure EJBCA
./docker/run-ejbca-bootstrap.sh

# Restart EJBCA
docker-compose restart ejbca

# Verify Serles
curl http://localhost:8080/directory
```

### 2. Domain Resolution (Optional)

For local testing with `demo.serles.local`:

```bash
echo "127.0.0.1 demo.serles.local" | sudo tee -a /etc/hosts
```

## Quick Start

### One Command Deploy

```bash
# Start Caddy (automatically obtains certificate)
docker-compose -f docker-compose.demo.yml up -d

# Access demo site
open https://localhost:8443
# or
open https://demo.serles.local:8443
```

That's it! Caddy automatically:

1. Starts web server
2. Requests certificate from Serles ACME
3. Configures TLS
4. Serves demo site over HTTPS

### View Logs

```bash
# Watch certificate provisioning
docker-compose -f docker-compose.demo.yml logs -f caddy

# You should see:
# - ACME account registration
# - Certificate request
# - Challenge validation
# - Certificate installation
```

## Configuration

### Environment Variables

Create `.env.demo` from template:

```bash
cp .env.demo.example .env.demo
```

Available variables:

| Variable      | Default                             | Description            |
| ------------- | ----------------------------------- | ---------------------- |
| `DEMO_DOMAIN` | `demo.serles.local`                 | Domain for certificate |
| `ACME_SERVER` | `http://serles-acme:8080/directory` | Serles ACME endpoint   |

### Custom Domain

```bash
# Edit .env.demo
DEMO_DOMAIN=example.com
ACME_SERVER=http://serles-acme:8080/directory

# Deploy
docker-compose -f docker-compose.demo.yml --env-file .env.demo up -d
```

### Ports

| Service | Port | Purpose                         |
| ------- | ---- | ------------------------------- |
| HTTP    | 8000 | ACME challenge + HTTPS redirect |
| HTTPS   | 8443 | Demo website with TLS           |

## Certificate Management

### View Certificate

```bash
# Access Caddy container
docker-compose -f docker-compose.demo.yml exec caddy sh

# View certificates
ls -la /data/caddy/certificates/

# Check certificate details
cat /data/caddy/certificates/acme-serles-acme-8080-directory/demo.serles.local/demo.serles.local.crt
```

### Manual Renewal

Caddy automatically renews certificates. To force renewal:

```bash
# Restart Caddy
docker-compose -f docker-compose.demo.yml restart caddy
```

### Different ACME Server

For production HTTPS ACME servers (no workaround needed):

```bash
# In .env.demo
ACME_SERVER=https://acme.production.com/directory

# Or use Let's Encrypt
ACME_SERVER=https://acme-v02.api.letsencrypt.org/directory
```

**Note**: The localhost proxy workaround is only needed for HTTP ACME servers (like local Serles). Production ACME servers use HTTPS and work directly with Caddy.

## Caddyfile Configuration

The [Caddyfile](demo/caddy/Caddyfile:1) is minimal and self-documenting:

```caddyfile
{
  # Use Serles ACME instead of Let's Encrypt
  acme_ca {$ACME_SERVER}
}

# HTTP - Challenge + Redirect
http://{$DOMAIN}:80 {
  redir https://{host}{uri}
}

# HTTPS - Auto TLS
https://{$DOMAIN}:443 {
  tls {
    issuer acme {
      dir {$ACME_SERVER}
    }
  }
  root * /srv
  file_server
}
```

## Technical Notes

### HTTP ACME Workaround

Caddy has a security requirement that ACME servers must use HTTPS, except for localhost/127.0.0.1 or 10.x.x.x private networks ([source code check](https://github.com/caddyserver/caddy/blob/master/modules/caddytls/acmeissuer.go)).

Since Serles ACME runs on HTTP (for local development), we use a workaround:

1. **ncat proxy** runs in the background inside Caddy container
2. Proxy forwards `localhost:4000` → `serles-acme:8080`
3. Caddy configured with `ACME_SERVER=http://127.0.0.1:4000/directory`
4. Caddy accepts `127.0.0.1` as valid "internal" ACME server
5. All ACME traffic flows through localhost proxy to Serles

This is implemented in the [custom entrypoint script](demo/caddy/entrypoint.sh:1) which:

- Installs `nmap-ncat` package
- Starts ncat proxy in background
- Launches Caddy normally

**Reference**: [Caddy Issue #1592](https://github.com/caddyserver/caddy/issues/1592) - Discussion of HTTP ACME in development environments

## Troubleshooting

### Certificate Not Obtained

**Check ACME proxy is running**:

```bash
# From Caddy container
docker-compose -f docker-compose.demo.yml exec caddy sh

# Check proxy is listening
nc -z 127.0.0.1 4000 && echo "Proxy OK" || echo "Proxy FAILED"

# Test proxy connectivity
wget -O- http://127.0.0.1:4000/directory
```

**Check Serles connectivity**:

```bash
# From Caddy container
docker-compose -f docker-compose.demo.yml exec caddy sh
wget -O- http://serles-acme:8080/directory
```

**Check Caddy logs**:

```bash
docker-compose -f docker-compose.demo.yml logs caddy | grep -i acme

# Look for:
# - "ACME proxy started" (proxy initialized)
# - "issuer":"acme-http://127.0.0.1:4000/directory" (using proxy)
# - NOT "error":"insecure CA URL" (means workaround failed)
```

### Challenge Validation Fails

**Verify network alias**:

```bash
# From Serles container
docker exec serles-acme ping -c 1 demo.serles.local
```

**Check challenge endpoint**:

```bash
curl http://localhost:8000/.well-known/acme-challenge/test
```

### Browser Shows Untrusted Certificate

This is expected for local development with EJBCA's self-signed CA.

**Solution 1 - Skip verification** (dev only):

```bash
curl -k https://localhost:8443
```

**Solution 2 - Trust EJBCA CA** (recommended):

```bash
# Export CA certificate
docker cp serles-ejbca:/mnt/persistent/ACMECA.pem .

# Import to system trust store (macOS)
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ACMECA.pem

# Or import to browser
```

## Production Deployment

For production use:

1. **Real domain** with proper DNS
2. **Production ACME server** (not local Serles)
3. **Proper firewall** rules (ports 80, 443)
4. **Monitoring** and alerting
5. **Backup** Caddy data volume
6. **Security hardening** (see Caddy docs)

Example production config:

```bash
# .env.demo
DEMO_DOMAIN=acme-demo.example.com
ACME_SERVER=https://acme.production.com/directory
```

## Cleanup

```bash
# Stop demo
docker-compose -f docker-compose.demo.yml down

# Remove volumes (deletes certificates!)
docker-compose -f docker-compose.demo.yml down -v
```

## Comparison: Caddy vs Nginx+Certbot

| Feature           | Caddy                | Nginx+Certbot                            |
| ----------------- | -------------------- | ---------------------------------------- |
| Containers        | 1                    | 3 (nginx + certbot-init + certbot-renew) |
| Configuration     | ~20 lines            | ~150 lines                               |
| ACME Client       | Built-in             | External (Certbot)                       |
| Auto-renewal      | Automatic            | Cron/timer required                      |
| First certificate | Automatic on startup | Manual run required                      |
| Complexity        | Low                  | Medium                                   |

## References

- [Caddy Documentation](https://caddyserver.com/docs/)
- [Caddy ACME](https://caddyserver.com/docs/automatic-https)
- [Serles ACME](https://github.com/thpham/serles-acme)
- [ACME Protocol (RFC 8555)](https://tools.ietf.org/html/rfc8555)
