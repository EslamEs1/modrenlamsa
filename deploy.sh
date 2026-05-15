#!/bin/bash
set -e

# ─── CONFIG ───────────────────────────────────────────────────────────────────
DOMAIN="allamsahaleasrih.online"
APP_DIR="/var/www/modrenlamsa"
NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"
GIT_REPO="https://github.com/EslamEs1/modrenlamsa.git"  # update if needed
BRANCH="main"
# ──────────────────────────────────────────────────────────────────────────────

GREEN="\033[0;32m"; YELLOW="\033[1;33m"; RED="\033[0;31m"; NC="\033[0m"
info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

[[ $EUID -ne 0 ]] && error "Run as root: sudo bash deploy.sh"

# ─── 1. SYSTEM PACKAGES ───────────────────────────────────────────────────────
info "Updating packages..."
apt-get update -qq
apt-get install -y -qq nginx git curl certbot python3-certbot-nginx ufw

# ─── 2. FIREWALL ──────────────────────────────────────────────────────────────
info "Configuring UFW firewall..."
ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw --force enable

# ─── 3. DEPLOY FILES ──────────────────────────────────────────────────────────
info "Deploying site files..."
mkdir -p "$APP_DIR"

if [[ -d "$APP_DIR/.git" ]]; then
    info "Pulling latest changes..."
    git -C "$APP_DIR" fetch origin
    git -C "$APP_DIR" reset --hard "origin/$BRANCH"
else
    info "Cloning repository..."
    git clone --depth=1 --branch "$BRANCH" "$GIT_REPO" "$APP_DIR"
fi

chown -R www-data:www-data "$APP_DIR"
chmod -R 755 "$APP_DIR"

# ─── 4. NGINX CONFIG ──────────────────────────────────────────────────────────
info "Writing Nginx config..."
cat > "$NGINX_CONF" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN www.$DOMAIN;

    root $APP_DIR;
    index index.html;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Gzip compression
    gzip on;
    gzip_types text/plain text/css application/javascript image/svg+xml;
    gzip_min_length 1024;

    # Cache static assets
    location ~* \.(css|js|jpg|jpeg|png|gif|ico|svg|woff2?|ttf|eot)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
        access_log off;
    }

    location / {
        try_files \$uri \$uri/ =404;
    }

    # Block hidden files
    location ~ /\. {
        deny all;
    }
}
EOF

# Enable site
ln -sf "$NGINX_CONF" "/etc/nginx/sites-enabled/$DOMAIN"
rm -f /etc/nginx/sites-enabled/default

nginx -t || error "Nginx config test failed"
systemctl reload nginx

# ─── 5. SSL (Let's Encrypt) ───────────────────────────────────────────────────
info "Obtaining SSL certificate..."
certbot --nginx \
    -d "$DOMAIN" -d "www.$DOMAIN" \
    --non-interactive \
    --agree-tos \
    --redirect \
    --email "eslamdeveloper1@gmail.com" || warn "SSL setup failed — site is live on HTTP only. Retry: certbot --nginx -d $DOMAIN"

# Auto-renew cron (certbot installs a systemd timer; this is a fallback)
if ! crontab -l 2>/dev/null | grep -q certbot; then
    (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet") | crontab -
fi

# ─── 6. NGINX AUTO-START ──────────────────────────────────────────────────────
systemctl enable nginx

# ─── DONE ─────────────────────────────────────────────────────────────────────
echo ""
info "Deployment complete!"
echo -e "  Site:    ${GREEN}https://$DOMAIN${NC}"
echo -e "  Files:   $APP_DIR"
echo -e "  Nginx:   $NGINX_CONF"
echo ""
