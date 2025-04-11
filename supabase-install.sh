#!/bin/bash
# Supabase installation script for Proxmox
# Installs Supabase in a Proxmox container
# No sudo support required

set -e

# Default values
POSTGRES_PASSWORD=$(openssl rand -base64 32)
JWT_SECRET=$(openssl rand -base64 32)
ANON_KEY=$(openssl rand -base64 32)
SERVICE_ROLE_KEY=$(openssl rand -base64 32)
DOMAIN="localhost"
PORT=3000
PGADMIN_EMAIL="admin@example.com"
PGADMIN_PASSWORD=$(openssl rand -base64 16)
DATA_DIR="/opt/supabase"

# Function to display script usage
print_usage() {
  echo "Usage: bash supabase-install.sh [options]"
  echo "Options:"
  echo "  --postgres-password   Set PostgreSQL password (default: random)"
  echo "  --domain              Set domain name (default: localhost)"
  echo "  --port                Set port number (default: 3000)"
  echo "  --data-dir            Set data directory (default: /opt/supabase)"
  echo "  --pgadmin-email       Set pgAdmin email (default: admin@example.com)"
  echo "  --pgadmin-password    Set pgAdmin password (default: random)"
  echo "  --help                Display this help message"
  exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --postgres-password)
      POSTGRES_PASSWORD="$2"
      shift 2
      ;;
    --domain)
      DOMAIN="$2"
      shift 2
      ;;
    --port)
      PORT="$2"
      shift 2
      ;;
    --data-dir)
      DATA_DIR="$2"
      shift 2
      ;;
    --pgadmin-email)
      PGADMIN_EMAIL="$2"
      shift 2
      ;;
    --pgadmin-password)
      PGADMIN_PASSWORD="$2"
      shift 2
      ;;
    --help)
      print_usage
      ;;
    *)
      echo "Unknown option: $1"
      print_usage
      ;;
  esac
done

# Create directories
mkdir -p "$DATA_DIR"/{db,storage,api,pgadmin}

# Install dependencies
echo "Installing dependencies..."
apt-get update
apt-get install -y curl apt-transport-https ca-certificates gnupg lsb-release git docker.io docker-compose

# Enable and start Docker
systemctl enable docker
systemctl start docker

# Create docker-compose.yml
echo "Creating docker-compose configuration..."
cat > "$DATA_DIR/docker-compose.yml" << EOL
version: '3.8'
services:
  postgres:
    image: supabase/postgres:15.1.0.117
    restart: always
    volumes:
      - ${DATA_DIR}/db:/var/lib/postgresql/data
    environment:
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_HOST_AUTH_METHOD: trust
    ports:
      - "5432:5432"

  studio:
    image: supabase/studio:latest
    restart: always
    depends_on:
      - postgres
      - gotrue
      - storage
      - kong
    environment:
      SUPABASE_URL: http://${DOMAIN}:${PORT}
      STUDIO_PG_META_URL: http://meta:8080
      SUPABASE_REST_URL: http://kong:8000/rest/v1/
      SUPABASE_ANON_KEY: ${ANON_KEY}
      SUPABASE_SERVICE_KEY: ${SERVICE_ROLE_KEY}
    ports:
      - "${PORT}:3000"

  kong:
    image: kong:2.8.1
    restart: always
    ports:
      - "8000:8000/tcp"
    environment:
      KONG_DATABASE: "off"
      KONG_DECLARATIVE_CONFIG: /var/lib/kong/kong.yml
      KONG_DNS_ORDER: LAST,A,CNAME
      KONG_PLUGINS: request-transformer,cors,key-auth,acl
    volumes:
      - ${DATA_DIR}/kong.yml:/var/lib/kong/kong.yml:ro

  gotrue:
    image: supabase/gotrue:v2.30.0
    restart: always
    depends_on:
      - postgres
    environment:
      GOTRUE_API_HOST: 0.0.0.0
      GOTRUE_API_PORT: 9999
      GOTRUE_DB_DRIVER: postgres
      GOTRUE_DB_DATABASE_URL: postgres://postgres:${POSTGRES_PASSWORD}@postgres:5432/postgres
      GOTRUE_JWT_SECRET: ${JWT_SECRET}
      GOTRUE_JWT_EXP: 3600
      GOTRUE_JWT_DEFAULT_GROUP_NAME: authenticated
      GOTRUE_SITE_URL: http://${DOMAIN}:${PORT}
      GOTRUE_SMTP_ADMIN_EMAIL: admin@example.com
      GOTRUE_MAILER_AUTOCONFIRM: "true"

  storage:
    image: supabase/storage-api:v0.28.0
    restart: always
    depends_on:
      - postgres
    environment:
      ANON_KEY: ${ANON_KEY}
      SERVICE_KEY: ${SERVICE_ROLE_KEY}
      POSTGREST_URL: http://rest:3000
      PGRST_JWT_SECRET: ${JWT_SECRET}
      DATABASE_URL: postgres://postgres:${POSTGRES_PASSWORD}@postgres:5432/postgres
      FILE_SIZE_LIMIT: 52428800
      STORAGE_BACKEND: file
      FILE_STORAGE_BACKEND_PATH: /var/lib/storage
      TENANT_ID: stub
      REGION: stub
    volumes:
      - ${DATA_DIR}/storage:/var/lib/storage

  rest:
    image: postgrest/postgrest:v10.1.2
    restart: always
    depends_on:
      - postgres
    environment:
      PGRST_DB_URI: postgres://postgres:${POSTGRES_PASSWORD}@postgres:5432/postgres
      PGRST_JWT_SECRET: ${JWT_SECRET}
      PGRST_DB_SCHEMAS: public,storage
      PGRST_DB_ANON_ROLE: anon

  meta:
    image: supabase/postgres-meta:v0.58.2
    restart: always
    depends_on:
      - postgres
    environment:
      PG_META_PORT: 8080
      PG_META_DB_URL: postgres://postgres:${POSTGRES_PASSWORD}@postgres:5432/postgres

  realtime:
    image: supabase/realtime:v2.5.1
    restart: always
    depends_on:
      - postgres
    environment:
      DB_URL: postgres://postgres:${POSTGRES_PASSWORD}@postgres:5432/postgres
      PORT: 4000
      JWT_SECRET: ${JWT_SECRET}
      SECURE_CHANNELS: "false"

  pgadmin:
    image: dpage/pgadmin4:latest
    restart: always
    depends_on:
      - postgres
    ports:
      - "5050:80"
    environment:
      PGADMIN_DEFAULT_EMAIL: ${PGADMIN_EMAIL}
      PGADMIN_DEFAULT_PASSWORD: ${PGADMIN_PASSWORD}
    volumes:
      - ${DATA_DIR}/pgadmin:/var/lib/pgadmin
EOL

# Create Kong configuration
cat > "$DATA_DIR/kong.yml" << EOL
_format_version: "2.1"
_transform: true

services:
  - name: rest-service
    url: http://rest:3000
    routes:
      - name: rest-route
        paths:
          - /rest
    plugins:
      - name: cors
      - name: key-auth
        config:
          hide_credentials: true
  - name: storage-service
    url: http://storage:5000
    routes:
      - name: storage-route
        paths:
          - /storage
    plugins:
      - name: cors
      - name: key-auth
        config:
          hide_credentials: true
  - name: gotrue-service
    url: http://gotrue:9999
    routes:
      - name: gotrue-route
        paths:
          - /auth
    plugins:
      - name: cors
  - name: realtime-service
    url: http://realtime:4000
    routes:
      - name: realtime-route
        paths:
          - /realtime
    plugins:
      - name: cors

consumers:
  - username: anon
    keyauth_credentials:
      - key: ${ANON_KEY}
  - username: service_role
    keyauth_credentials:
      - key: ${SERVICE_ROLE_KEY}
EOL

# Create startup script
cat > "$DATA_DIR/start-supabase.sh" << EOL
#!/bin/bash
cd "$DATA_DIR"
docker-compose up -d
EOL

# Create status script
cat > "$DATA_DIR/status-supabase.sh" << EOL
#!/bin/bash
cd "$DATA_DIR"
docker-compose ps
EOL

# Create stop script
cat > "$DATA_DIR/stop-supabase.sh" << EOL
#!/bin/bash
cd "$DATA_DIR"
docker-compose down
EOL

# Make scripts executable
chmod +x "$DATA_DIR/start-supabase.sh"
chmod +x "$DATA_DIR/status-supabase.sh"
chmod +x "$DATA_DIR/stop-supabase.sh"

# Create service files
cat > /etc/systemd/system/supabase.service << EOL
[Unit]
Description=Supabase Service
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$DATA_DIR
ExecStart=$DATA_DIR/start-supabase.sh
ExecStop=$DATA_DIR/stop-supabase.sh

[Install]
WantedBy=multi-user.target
EOL

# Enable and start services
systemctl daemon-reload
systemctl enable supabase
systemctl start supabase

# Print success message
echo "======================================================================================"
echo "Supabase has been installed successfully!"
echo "======================================================================================"
echo "PostgreSQL Password: $POSTGRES_PASSWORD"
echo "Anon Key: $ANON_KEY"
echo "Service Role Key: $SERVICE_ROLE_KEY"
echo "pgAdmin Email: $PGADMIN_EMAIL"
echo "pgAdmin Password: $PGADMIN_PASSWORD"
echo "======================================================================================"
echo "Access the Supabase Studio at: http://$DOMAIN:$PORT"
echo "Access pgAdmin at: http://$DOMAIN:5050"
echo "PostgreSQL is available at: $DOMAIN:5432"
echo "======================================================================================"
echo "Data directory: $DATA_DIR"
echo "Start Supabase: systemctl start supabase"
echo "Stop Supabase: systemctl stop supabase"
echo "Check status: systemctl status supabase"
echo "======================================================================================"