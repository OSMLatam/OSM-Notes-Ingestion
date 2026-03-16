---
title: "Installation and Dependencies Guide"
description: "Complete guide to install dependencies and set up OSM-Notes-Ingestion for development"
version: "1.0.0"
last_updated: "2026-03-15"
author: "AngocA"
tags:
  - "installation"
  - "dependencies"
  - "setup"
audience:
  - "developers"
  - "system-admins"
project: "OSM-Notes-Ingestion"
status: "active"
---

# Installation and Dependencies Guide

Complete guide to install all dependencies and set up OSM-Notes-Ingestion for development and production.

## Table of Contents

1. [System Requirements](#system-requirements)
2. [System Dependencies](#system-dependencies)
3. [Database Setup](#database-setup)
4. [Project Installation](#project-installation)
5. [Configuration](#configuration)
6. [Verification](#verification)
7. [Troubleshooting](#troubleshooting)

---

## System Requirements

### Operating System

- **Linux** (Ubuntu 20.04+ / Debian 11+ recommended)
- **Bash** 4.0 or higher
- **Git** for cloning repositories

### Hardware Requirements

- **CPU**: 2+ cores recommended
- **RAM**: 4GB minimum, 8GB+ recommended
- **Disk**: 50GB+ free space (for Planet files and database)
- **Network**: Stable internet connection for downloading Planet files and API access

---

## System Dependencies

### Required Software

Install all required dependencies on Ubuntu/Debian:

```bash
# Update package list
sudo apt-get update

# PostgreSQL with PostGIS extension
sudo apt-get install -y postgresql postgis
# If CREATE EXTENSION postgis fails, install the PostGIS extension for your PostgreSQL major version (14, 15, 16, etc.):
# PG_MAJOR=$(psql --version | sed -n 's/.* \([0-9]*\)\..*/\1/p') && sudo apt-get install -y "postgresql-${PG_MAJOR}-postgis-3"
# If CREATE EXTENSION btree_gist fails, install the contrib package for your version (e.g. postgresql-17-contrib or postgresql-contrib).

# Standard UNIX utilities
sudo apt-get install -y curl jq bc

# Parallel processing
sudo apt-get install -y parallel

# Download tool for parallel downloads
sudo apt-get install -y aria2

# XML validation (optional, only if SKIP_XML_VALIDATION=false)
sudo apt-get install -y libxml2-utils

# Geographic tools (GDAL)
sudo add-apt-repository ppa:ubuntugis/ppa -y
sudo apt-get update
sudo apt-get install -y gdal-bin

# Node.js and npm (for geographic tools)
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# Install Node.js tools globally
sudo npm install -g osmtogeojson
sudo npm install -g ajv-cli
# Note: You may see npm "deprecated" warnings (e.g. @xmldom/xmldom, inflight, glob). These come from
# upstream dependencies of osmtogeojson and ajv-cli; the tools work correctly for this project.

# Email notifications (for monitoring alerts)
sudo apt-get install -y mutt

# Git (if not already installed)
sudo apt-get install -y git
```

### Verify Installation

```bash
# Check PostgreSQL version
psql --version  # Should be 12+

# Check PostGIS is available (extension is created per-database later, e.g. in database "notes")
sudo -u postgres psql -d postgres -c "SELECT name, default_version FROM pg_available_extensions WHERE name = 'postgis';"

# Check Bash version
bash --version  # Should be 4.0+

# Check other tools
parallel --version
jq --version
curl --version
node --version  # Should be 20+
npm --version
gdalinfo --version
```

On Linux, PostgreSQL often uses *peer* authentication for local connections: the OS user must match the
database role. Running `sudo -u postgres psql ...` ensures the connection runs as the `postgres` system user.

**How to verify peer is active:** Check that local connections use method `peer` in `pg_hba.conf`:

```bash
# Show relevant lines (local connections and auth method)
sudo grep -E '^\s*local\s' /etc/postgresql/*/main/pg_hba.conf
```

You should see lines ending in `peer` (e.g. `local all all peer`). After editing `pg_hba.conf`, run `sudo systemctl reload postgresql` for changes to take effect.

---

## Database Setup

### 1. Create PostgreSQL User and Database

```bash
# Switch to postgres user
sudo su - postgres

# Create user and database
psql << EOF
CREATE USER notes WITH PASSWORD 'your_secure_password_here';
ALTER USER notes CREATEDB;
CREATE DATABASE notes WITH OWNER notes;
\q
EOF

exit
```

### 2. Enable PostGIS Extension

Run as the `postgres` system user so peer authentication succeeds (the `postgres` role can create extensions in any database):

```bash
sudo -u postgres psql -d notes << EOF
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS btree_gist;
\q
EOF
```

### 3. Verify Database Setup

```bash
sudo -u postgres psql -d notes -c "SELECT PostGIS_version();"
sudo -u postgres psql -d notes -c "\dx"  # List installed extensions
```

---

## Project Installation

### 1. Clone Repository with Submodules

```bash
# Clone with submodules (recommended)
git clone --recurse-submodules https://github.com/OSM-Notes/OSM-Notes-Ingestion.git
cd OSM-Notes-Ingestion

# Or if already cloned, initialize submodules
git submodule update --init --recursive
```

**Production (optional):** For a production server, installing under `/opt` follows the Linux FHS and keeps application code separate from user data. Example:

```bash
sudo mkdir -p /opt
sudo git clone --recurse-submodules https://github.com/OSM-Notes/OSM-Notes-Ingestion.git /opt/osm-notes-ingestion
cd /opt/osm-notes-ingestion
# Then create a dedicated data directory (see step 4) and set DATA_DIR in etc/properties.sh
```

### 2. Verify Submodule Installation

```bash
# Check submodule status
git submodule status

# Verify common functions exist
ls -la lib/osm-common/commonFunctions.sh
ls -la lib/osm-common/validationFunctions.sh
ls -la lib/osm-common/errorHandlingFunctions.sh
ls -la lib/osm-common/bash_logger.sh
```

### 3. Install System Directories (Optional - for Production)

For production installations, create system directories:

```bash
sudo bin/scripts/install_directories.sh
```

This creates:
- `/var/log/osm-notes-ingestion/` - Log files (with subdirectories: daemon, processing, monitoring)
- `/var/tmp/osm-notes-ingestion/` - Temporary files (with subdirectories: planet, overpass, api)
- `/var/run/osm-notes-ingestion/` - Lock files (required for daemon operation)

The script sets proper ownership (`notes:maptimebogota` by default) and permissions:
- Logs: `755` (readable by group, writable by owner)
- Temp: `775` (writable by owner and group)
- Locks: `775` (writable by owner and group)

**Note**: For development, the system will use `/tmp` directories automatically. However, for production with systemd service, the lock directory `/var/run/osm-notes-ingestion` must exist and be writable by the service user.

### 4. Data Directory (Production)

The scripts read and write backup data (note locations, countries, maritimes) under a single **data directory**. By default this is `data/` inside the project root. When the service runs as user `notes` (e.g. under systemd), that user must be able to write there. If the repo was cloned by another user, you can either fix ownership of the repo `data/` or use a separate directory (no permission changes in the repo needed).

**Option A – Keep default path, fix ownership:** Set ownership so the service user can write to the project `data/` directory (adjust paths and group to match your installation):

```bash
# Use the same user and group as in install_directories.sh (e.g. notes:maptimebogota)
sudo chown -R notes:maptimebogota /path/to/OSM-Notes-Ingestion/data
```

**Option B – Use a dedicated data directory (recommended for production):** Set `DATA_DIR` in `etc/properties.sh`. The daemon loads that file on startup, so you do **not** need to change the systemd service file. The service then does **not** need write access to the repository. The recommended path is `/var/lib/osm-notes-ingestion`. Under the Linux FHS, `/var/lib` is for **application state data** (persistent data that the program writes and updates), not for code libraries (those live under `/usr/lib`). Examples: `/var/lib/postgresql`, `/var/lib/dpkg`.

```bash
# In etc/properties.sh (or export before starting the daemon)
export DATA_DIR="/var/lib/osm-notes-ingestion"
```

Create the data directory and give ownership to the service user (only this directory needs to be writable by the service):

```bash
sudo mkdir -p /var/lib/osm-notes-ingestion
sudo chown notes:maptimebogota /var/lib/osm-notes-ingestion
```

All backup and generated data (noteLocation, countries.geojson, maritimes.geojson, eez_analysis) will then be read from and written to `DATA_DIR`. See `bin/Environment_Variables.md` for the full `DATA_DIR` reference.

Ensure the chosen data directory exists and has correct permissions before starting the daemon or running `processPlanetNotes.sh --base` / `updateCountries.sh --base`.

---

## Configuration

### 1. Environment Variables

Create a configuration file or set environment variables:

```bash
# Copy example configuration
cp etc/properties.sh.example etc/properties.sh

# Edit configuration
nano etc/properties.sh
```

### 2. Required Configuration Variables

Copy the example and edit `etc/properties.sh` (see `etc/properties.sh.example`). The example already defines **DBNAME** and **DB_USER**; set them to your database and PostgreSQL role.

**Required for all setups** (in `etc/properties.sh` or environment):

```bash
# Database connection (names match etc/properties.sh.example)
export DBNAME="notes"
export DB_USER="notes"
```

**Optional** — only needed for remote connections or password authentication (not for local peer auth):

```bash
export DB_HOST="localhost"   # Omit for peer auth (Unix socket)
export DB_PORT="5432"
export DB_PASSWORD="your_secure_password_here"
```

**Other common options** (in `etc/properties.sh` or environment):

```bash
export LOG_LEVEL="INFO"       # TRACE, DEBUG, INFO, WARN, ERROR, FATAL
export SKIP_XML_VALIDATION="false"  # Set to "true" to skip XML validation
```

### 3. Source Configuration

```bash
# Source the configuration file
source etc/properties.sh

# Or export variables directly
export DBNAME="notes"
export DB_USER="notes"
# ... etc
```

---

## Verification

### 1. Verify Prerequisites

There is no standalone script that only checks prerequisites. You can:

**Manual check** — Use the [Verify Installation](#verify-installation) commands earlier in this doc
(psql, jq, curl, parallel, node, gdalinfo, etc.) and the [Test Database Connection](#2-test-database-connection) below.

**Automated check (optional)** — Install [BATS](https://bats-core.readthedocs.io/) and run the
prerequisite tests:

```bash
# Install BATS: Debian/Ubuntu  sudo apt install bats-core  (or  npm install -g bats)
bats tests/unit/bash/prerequisites_commands.test.bats
bats tests/unit/bash/prerequisites_database.test.bats
```

When you run the main scripts (e.g. `processAPINotes.sh`), they validate prerequisites at startup
and exit with an error if something is missing—but that is part of normal execution, not a separate
verification step.

### 2. Test Database Connection

```bash
# With peer auth (run as postgres OS user)
sudo -u postgres psql -d notes -c "SELECT version();"
sudo -u postgres psql -d notes -c "SELECT PostGIS_version();"

# With password auth (if DB_HOST/DB_PASSWORD are set)
psql -h localhost -U notes -d notes -c "SELECT version();"
psql -h localhost -U notes -d notes -c "SELECT PostGIS_version();"
```

### 3. Run Tests

```bash
# Run all tests
./tests/run_all_tests.sh

# Run specific test suites
./tests/unit/bash/run_unit_tests.sh
```

### 4. Verify Entry Points

```bash
# Check available entry points
cat bin/Entry_Points.md

# Verify scripts are executable
ls -la bin/process/*.sh
```

---

## Internal Dependencies

### Project Dependencies

**None** - This is the base project and has no dependencies on other OSM-Notes repositories.

However, other projects depend on this one:
- **OSM-Notes-Analytics** requires this project (reads from base tables)
- **OSM-Notes-WMS** requires this project (uses same database)
- **OSM-Notes-Monitoring** monitors this project

### Git Submodule

This project uses **OSM-Notes-Common** as a Git submodule:
- Location: `lib/osm-common/`
- Contains: Shared Bash functions
- **Required**: Yes (must be initialized)

---

## Troubleshooting

### Submodule Issues

If you see errors like `/lib/osm-common/commonFunctions.sh: No such file or directory`:

```bash
# Initialize submodules
git submodule update --init --recursive

# Verify submodule exists
ls -la lib/osm-common/commonFunctions.sh

# If still having issues, re-initialize
git submodule deinit -f lib/osm-common
git submodule update --init --recursive
```

### Database Connection Issues

```bash
# Check PostgreSQL is running
sudo systemctl status postgresql

# Check user permissions
psql -U postgres -c "\du notes"

# Test connection
psql -h localhost -U notes -d notes
```

### Missing Dependencies

```bash
# Check if all tools are installed
which psql parallel jq curl node npm gdalinfo

# Install missing tools (see System Dependencies section above)
```

### Permission Issues

```bash
# Ensure scripts are executable
chmod +x bin/process/*.sh
chmod +x bin/monitor/*.sh
chmod +x bin/scripts/*.sh

# Check directory permissions
ls -la /var/log/osm-notes-ingestion/  # If using installed mode
ls -la /tmp/osm-notes-ingestion/      # If using fallback mode
```

**Data directory (production):** If the process runs as user `notes` and you see `Permission denied` when writing to `data/` (e.g. when saving `noteLocation.csv.zip`), fix ownership so the service user can write:

```bash
# Replace path and group with your installation (same user/group as install_directories.sh)
sudo chown -R notes:maptimebogota /home/notes/OSM-Notes-Ingestion/data
```

### Full cleanup (cleanupAll.sh) in production

To **delete all data** (tables, sequences, etc.) you must run `cleanupAll.sh` as the **database owner** (the role that owns the tables, usually `notes`). With peer authentication, that means running as the same OS user.

- **Wrong:** `sudo ./bin/cleanupAll.sh --all` — runs as `root`; PostgreSQL sees role `root`, which may not exist or cannot connect to database `notes`, so you get "Database notes does not exist".
- **Wrong:** `./bin/cleanupAll.sh --all` as `angoca` — connects as `angoca`; if tables are owned by role `notes`, `angoca` cannot `DROP` them, so you get "Failed to drop API tables" and "Check Tables failed".
- **Correct:** Run as the service/DB owner:

```bash
cd /opt/osm-notes-ingestion
sudo -u notes ./bin/cleanupAll.sh --all
```

Ensure `etc/properties.sh` is loaded (the script sources it) and that `DBNAME`/`DB_USER` match your database and owner (e.g. `notes`). See [Cleanup_Integration.md](Cleanup_Integration.md) for options.

---

## Next Steps

After installation:

1. **Read Entry Points**: `bin/Entry_Points.md` - Which scripts to use
2. **Review Environment Variables**: `bin/Environment_Variables.md` - Configuration options
3. **Run Tests**: `./tests/run_all_tests.sh` - Verify installation
4. **Read Documentation**: `docs/README.md` - Complete documentation index

---

## Related Documentation

- [Entry Points](bin/Entry_Points.md) - Which scripts can be called directly
- [Environment Variables](bin/Environment_Variables.md) - Complete configuration reference
- [Local Setup Guide](Local_Setup.md) - Development environment setup
- [PostgreSQL Setup](Postgresql_Setup.md) - Database configuration details
- [Testing Guide](Testing_Guide.md) - How to run tests
