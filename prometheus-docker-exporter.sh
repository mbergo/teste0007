#!/bin/bash
# This script installs the docker_exporter for Prometheus on a Debian system.
# It downloads the binary from GitHub, installs it to /usr/local/bin,
# creates a dedicated system user, and sets up a systemd service.
#
# Requirements:
#   - Root privileges (or run with sudo)
#   - curl and tar installed (if not, install via apt-get)
#   - Docker installed and running (the exporter reads /var/run/docker.sock)

set -e  # Exit immediately if a command exits with a non-zero status

# Check for root privileges.
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Please run with sudo or as root."
    exit 1
fi

# Check if required commands exist (curl and tar)
for cmd in curl tar; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Required command '$cmd' is not installed. Installing..."
        apt-get update && apt-get install -y "$cmd"
    fi
done

# Variables: set the version of docker_exporter you want to install.
EXPORTER_VERSION="0.6.0"
DOWNLOAD_URL="https://github.com/wrouesnel/docker_exporter/releases/download/v${EXPORTER_VERSION}/docker_exporter-${EXPORTER_VERSION}.linux-amd64.tar.gz"
TMP_DIR="/tmp/docker_exporter_install"
INSTALL_DIR="/usr/local/bin"
BINARY_NAME="docker_exporter"  # Expected binary name after extraction
SERVICE_FILE="/etc/systemd/system/docker_exporter.service"

# Create a temporary directory for downloading.
mkdir -p "$TMP_DIR"
cd "$TMP_DIR"

echo "Downloading docker_exporter version ${EXPORTER_VERSION} from:"
echo "  ${DOWNLOAD_URL}"
curl -L -o docker_exporter.tar.gz "$DOWNLOAD_URL"

# Verify download (you can add checksum verification here if desired)
if [ ! -f docker_exporter.tar.gz ]; then
    echo "Download failed: docker_exporter.tar.gz not found."
    exit 1
fi

# Extract the tarball.
tar -xzf docker_exporter.tar.gz

# Check if the expected binary is present; if not, try to locate it.
if [ ! -f "$BINARY_NAME" ]; then
    echo "Binary '$BINARY_NAME' not found in extracted files. Searching..."
    FOUND_BINARY=$(find . -type f -name docker_exporter | head -n 1)
    if [ -z "$FOUND_BINARY" ]; then
        echo "Failed to locate the docker_exporter binary."
        exit 1
    else
        BINARY_NAME="$FOUND_BINARY"
    fi
fi

# Move the binary to the installation directory and set executable permissions.
echo "Installing docker_exporter to ${INSTALL_DIR}/docker_exporter"
mv "$BINARY_NAME" "${INSTALL_DIR}/docker_exporter"
chmod +x "${INSTALL_DIR}/docker_exporter"

# Clean up temporary files.
cd /
rm -rf "$TMP_DIR"

# Check for the Docker socket. Warn if not found.
if [ ! -S /var/run/docker.sock ]; then
    echo "Warning: /var/run/docker.sock does not exist. Please ensure Docker is installed and running."
fi

# Create a dedicated system user for running the exporter (if it does not already exist).
if ! id -u docker_exporter >/dev/null 2>&1; then
    echo "Creating system user 'docker_exporter'..."
    useradd --system --no-create-home --shell /usr/sbin/nologin docker_exporter
fi

# Add the docker_exporter user to the 'docker' group (if the group exists) so it can access /var/run/docker.sock.
if getent group docker >/dev/null; then
    usermod -aG docker docker_exporter
fi

# Check if systemd is available. If so, create a service file.
if command -v systemctl >/dev/null 2>&1; then
    echo "Creating systemd service file at ${SERVICE_FILE}..."
    cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=Docker Exporter for Prometheus
After=network.target docker.service
Requires=docker.service

[Service]
User=docker_exporter
Group=docker_exporter
# If you need to pass additional flags (e.g., to change the listening port), modify ExecStart accordingly.
ExecStart=${INSTALL_DIR}/docker_exporter
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd to pick up the new service file.
    echo "Reloading systemd daemon..."
    systemctl daemon-reload

    # Enable and start the docker_exporter service.
    echo "Enabling and starting the docker_exporter service..."
    systemctl enable docker_exporter
    systemctl start docker_exporter

    echo "docker_exporter installation complete."
    echo "You can check its status using: systemctl status docker_exporter"
else
    # For systems without systemd, instruct the user how to run the exporter manually.
    echo "Systemd does not appear to be available on this system."
    echo "To run the exporter manually, execute the following command:"
    echo "nohup ${INSTALL_DIR}/docker_exporter > /var/log/docker_exporter.log 2>&1 &"
    echo "Then, add the command to your init system as appropriate."
fi
