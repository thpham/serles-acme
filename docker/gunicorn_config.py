"""
Gunicorn configuration for Serles ACME Server
Production-ready settings with gevent workers for async I/O
"""

import multiprocessing
import os

# TLS configuration (optional)
tls_enabled = os.getenv("TLS_ENABLED", "false").lower() in ("true", "1", "yes")
tls_port = int(os.getenv("TLS_PORT", "8443"))
http_port = int(os.getenv("HTTP_PORT", "8080"))

# Server socket - bind to appropriate port based on TLS setting
bind = f"0.0.0.0:{tls_port if tls_enabled else http_port}"
backlog = 2048

# Worker processes
# For gevent workers, use fewer workers (2-4) since each can handle many concurrent connections
# Unlike sync workers, gevent doesn't need (2*CPU + 1) workers
workers = int(os.getenv("GUNICORN_WORKERS", min(2, multiprocessing.cpu_count() + 1)))
worker_class = "gevent"  # Async workers for I/O-bound operations (EJBCA SOAP calls)
worker_connections = 1000
threads = 2  # Additional threads per worker
timeout = 120  # Timeout for EJBCA API calls (in seconds)
keepalive = 5

# Worker lifecycle
max_requests = 1000  # Restart workers after N requests (prevents memory leaks)
max_requests_jitter = 50  # Add randomness to max_requests
graceful_timeout = 30

# Logging
accesslog = "-"  # Log to stdout
errorlog = "-"   # Log to stderr
loglevel = os.getenv("LOG_LEVEL", "info")
access_log_format = '%(h)s %(l)s %(u)s %(t)s "%(r)s" %(s)s %(b)s "%(f)s" "%(a)s" %(D)s'

# Process naming
proc_name = "serles-acme"

# Server mechanics
daemon = False
pidfile = None
user = None  # Run as current user (already non-root in container)
group = None
tmp_upload_dir = None

# SSL/TLS configuration (optional - controlled by TLS_ENABLED env var)
# By default, TLS is disabled (for k8s with ingress TLS termination)
# Enable for end-to-end encryption or local development with example clients
if tls_enabled:
    keyfile = os.getenv("TLS_KEY_FILE", "/etc/serles/tls/server.key")
    certfile = os.getenv("TLS_CERT_FILE", "/etc/serles/tls/server.crt")
else:
    keyfile = None
    certfile = None

# Application
# preload_app disabled for gevent to avoid MonkeyPatchWarning
# Gevent workers need to patch stdlib before application imports occur
preload_app = False

# Hooks for application lifecycle
def on_starting(server):
    """Called just before the master process is initialized."""
    server.log.info("Starting Serles ACME Server")

def on_reload(server):
    """Called to recycle workers during a reload via SIGHUP."""
    server.log.info("Reloading Serles ACME Server")

def when_ready(server):
    """Called just after the server is started."""
    protocol = "HTTPS" if tls_enabled else "HTTP"
    server.log.info("Serles ACME Server is ready. Listening on %s (%s)", bind, protocol)

def on_exit(server):
    """Called just before exiting Gunicorn."""
    server.log.info("Shutting down Serles ACME Server")

def worker_int(worker):
    """Called when a worker receives the SIGINT or SIGQUIT signal."""
    worker.log.info("Worker received INT or QUIT signal")

def worker_abort(worker):
    """Called when a worker receives the SIGABRT signal."""
    worker.log.info("Worker received SIGABRT signal")
