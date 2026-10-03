#!/bin/bash
# Deploy PocketBase on VDS for MIREA Career App
# Run as root or with sudo
# Usage: bash deploy.sh

set -euo pipefail

DOMAIN="vmt-mireacareer.l1ratch.ru"
DEPLOY_DIR="/opt/mirea-pocketbase"

echo "=== PocketBase deployment for $DOMAIN ==="
echo "Deploy directory: $DEPLOY_DIR"

# 1. Check Docker
if ! command -v docker &> /dev/null; then
    echo "Docker not found. Install first:"
    echo "  curl -fsSL https://get.docker.com | sh"
    exit 1
fi

if ! docker compose version &> /dev/null; then
    echo "Docker Compose v2 not found. Install docker-compose-plugin."
    exit 1
fi

# 2. Create deploy directory
mkdir -p "$DEPLOY_DIR"
cd "$DEPLOY_DIR"

# 3. Check TLS certificate exists
CERT_PATH="/etc/letsencrypt/live/l1ratch.ru/fullchain.pem"
KEY_PATH="/etc/letsencrypt/live/l1ratch.ru/privkey.pem"

if [ ! -f "$CERT_PATH" ] || [ ! -f "$KEY_PATH" ]; then
    echo "WARNING: Wildcard cert not found at $CERT_PATH"
    echo "Check your cert paths and update nginx.conf accordingly."
    echo ""
    echo "Available certs:"
    ls -la /etc/letsencrypt/live/ 2>/dev/null || echo "  No certs in /etc/letsencrypt/live/"
    echo ""
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# 4. Copy config files (если запускаем из репозитория)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/docker-compose.yml" ]; then
    cp "$SCRIPT_DIR/docker-compose.yml" "$DEPLOY_DIR/"
    cp "$SCRIPT_DIR/nginx.conf" "$DEPLOY_DIR/"
    echo "Config files copied to $DEPLOY_DIR"
else
    echo "docker-compose.yml not found next to this script."
    echo "Place docker-compose.yml and nginx.conf in $DEPLOY_DIR manually."
    exit 1
fi

# 5. Pull images
echo "Pulling Docker images..."
docker compose pull

# 6. Start services
echo "Starting PocketBase + Nginx..."
docker compose up -d

# 7. Wait for health check
echo "Waiting for PocketBase to be healthy..."
for i in $(seq 1 30); do
    if docker compose exec -T pocketbase wget --spider -q http://localhost:8090/api/health 2>/dev/null; then
        echo "PocketBase is healthy!"
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo "Timeout waiting for PocketBase. Check logs:"
        echo "  docker compose logs pocketbase"
        exit 1
    fi
    sleep 2
done

# 8. Show status
echo ""
echo "=== Deployment complete ==="
echo "Admin UI: https://$DOMAIN/_/"
echo "API:      https://$DOMAIN/api/"
echo ""
echo "Next steps:"
echo "  1. Open https://$DOMAIN/_/ and create admin account"
echo "  2. Create collections (see schema.md)"
echo "  3. Set API rules for public read access"
echo ""
echo "Useful commands:"
echo "  cd $DEPLOY_DIR"
echo "  docker compose logs -f     # Follow logs"
echo "  docker compose restart     # Restart services"
echo "  docker compose down        # Stop everything"
echo "  docker compose up -d       # Start again"
