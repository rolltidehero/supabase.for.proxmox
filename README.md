# Supabase for Proxmox

A script to install Supabase in a Proxmox container.

## Features

- Complete Supabase stack deployment via Docker Compose
- Automated installation with sensible defaults
- Custom configuration options
- SystemD service integration
- No sudo required

## Requirements

- Proxmox container with Debian/Ubuntu
- At least 4GB RAM recommended
- At least 20GB disk space
- Docker and Docker Compose capability
- Internet connectivity

## Installation

1. Download the installation script:
```bash
wget -O supabase-install.sh https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/install/supabase-install.sh
```

2. Make it executable:
```bash
chmod +x supabase-install.sh
```

3. Run the script:
```bash
./supabase-install.sh
```

## Configuration Options

You can customize the installation with the following options:

```bash
./supabase-install.sh --domain yourdomain.com --port 8000 --data-dir /path/to/data
```

Available options:

- `--postgres-password`: Set PostgreSQL password (default: random)
- `--domain`: Set domain name (default: localhost)
- `--port`: Set port number (default: 3000)
- `--data-dir`: Set data directory (default: /opt/supabase)
- `--pgadmin-email`: Set pgAdmin email (default: admin@example.com)
- `--pgadmin-password`: Set pgAdmin password (default: random)

## Usage

After installation, you can manage the Supabase service with:

```bash
# Start Supabase
systemctl start supabase

# Stop Supabase
systemctl stop supabase

# Check status
systemctl status supabase
```

Access Supabase at:
- Supabase Studio: http://your-domain-or-ip:3000
- PostgreSQL: your-domain-or-ip:5432
- pgAdmin: http://your-domain-or-ip:5050

## Backup and Restore

All data is stored in the data directory (default: /opt/supabase). To backup your Supabase installation:

1. Stop the service:
```bash
systemctl stop supabase
```

2. Backup the data directory:
```bash
tar -czvf supabase-backup.tar.gz /opt/supabase
```

To restore:
1. Extract the backup:
```bash
tar -xzvf supabase-backup.tar.gz -C /
```

2. Start the service:
```bash
systemctl start supabase
```

## Troubleshooting

If you experience issues:

1. Check service status:
```bash
systemctl status supabase
```

2. View container logs:
```bash
cd /opt/supabase && docker-compose logs
```

3. Check individual service:
```bash
cd /opt/supabase && docker-compose logs [service-name]
```

Where [service-name] is one of: postgres, studio, kong, gotrue, storage, rest, meta, realtime, pgadmin

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.