#!/bin/bash
echo "================================================"
echo "Installing IoT Soil Monitoring System"
echo "================================================"

# ========================
# COLOR OUTPUT
# ========================
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

print_green() {
    echo -e "${GREEN}[✓] $1${NC}"
}

print_yellow() {
    echo -e "${YELLOW}[!] $1${NC}"
}

print_red() {
    echo -e "${RED}[✗] $1${NC}"
}

# ========================
# CHECK RUN AS ROOT
# ========================
if [[ $EUID -ne 0 ]]; then
    print_red "This script must be run as root. Use: sudo ./install.sh"
    exit 1
fi

# ========================
# CREATE SENSOR USER
# ========================
print_green "[1/9] Creating sensor user account..."

# Check if user already exists
if id "sensor" &>/dev/null; then
    print_yellow "User 'sensor' already exists"
else
    # Create sensor user with home directory
    useradd -m -s /bin/bash -G sudo,dialout sensor
    echo "sensor:sensor123" | chpasswd
    print_green "User 'sensor' created with password 'sensor123'"
    print_yellow "⚠️  Please change the password after installation: sudo passwd sensor"
fi

# ========================
# SYSTEM UPDATE
# ========================
print_green "[2/9] Updating system packages..."
apt update
apt upgrade -y

# ========================
# INSTALL PYTHON & DEPENDENCIES
# ========================
print_green "[3/9] Installing Python and dependencies..."
apt install python3 python3-pip python3-venv -y

# ========================
# INSTALL PYTHON PACKAGES AS SENSOR USER
# ========================
print_green "[4/9] Installing Python packages for sensor user..."

# Switch to sensor user to install packages
sudo -u sensor bash << 'EOF'
pip3 install --user pyserial==3.5
pip3 install --user pandas==2.0.3
pip3 install --user requests==2.31.0
EOF

print_green "Python packages installed for sensor user"

# ========================
# CREATE APPLICATION STRUCTURE
# ========================
print_green "[5/9] Setting up application directory structure..."

# Main application directory
APP_DIR="/home/sensor/iot-soil-monitoring-system"
mkdir -p $APP_DIR
chown sensor:sensor $APP_DIR
chmod 755 $APP_DIR

# Data storage directory
DATA_DIR="/home/sensor/sensor_data"
mkdir -p $DATA_DIR
chown sensor:sensor $DATA_DIR
chmod 755 $DATA_DIR

# Logs directory
LOG_DIR="/home/sensor/sensor_logs"
mkdir -p $LOG_DIR
chown sensor:sensor $LOG_DIR
chmod 755 $LOG_DIR

# Gateway data directory
GATEWAY_DATA_DIR="/home/sensor/gateway_data"
mkdir -p $GATEWAY_DATA_DIR
chown sensor:sensor $GATEWAY_DATA_DIR
chmod 755 $GATEWAY_DATA_DIR

print_green "Application directories created:"
print_green "  - $APP_DIR (Python code)"
print_green "  - $DATA_DIR (sensor data storage)"
print_green "  - $LOG_DIR (system logs)"
print_green "  - $GATEWAY_DATA_DIR (gateway offline storage)"

# ========================
# ENABLE SERIAL INTERFACE
# ========================
print_green "[6/9] Configuring serial interface..."

# Disable serial console but enable serial port hardware
raspi-config nonint do_serial 2

# Add sensor user to dialout group for serial access
usermod -a -G dialout sensor

# Set correct permissions for serial ports
chmod 666 /dev/ttyUSB0 2>/dev/null || true
chmod 666 /dev/ttyACM0 2>/dev/null || true

print_green "Serial interface configured"
print_green "User 'sensor' added to dialout group"

# ========================
# SETUP AUTO-START SERVICE
# ========================
print_green "[7/9] Setting up auto-start service..."

# Create systemd service file
SERVICE_FILE="/etc/systemd/system/soil-monitor.service"
tee $SERVICE_FILE > /dev/null << EOF
[Unit]
Description=Soil Monitoring IoT System
After=network.target
Wants=network.target
StartLimitIntervalSec=500
StartLimitBurst=5

[Service]
Type=simple
User=sensor
WorkingDirectory=$APP_DIR
ExecStart=/usr/bin/python3 $APP_DIR/MainController.py
Environment="PATH=/home/sensor/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Environment="PYTHONPATH=$APP_DIR"
Restart=always
RestartSec=10
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=soil-monitor

# Security enhancements
NoNewPrivileges=true
ProtectSystem=strict
PrivateTmp=true
ReadWritePaths=$DATA_DIR $LOG_DIR $GATEWAY_DATA_DIR

[Install]
WantedBy=multi-user.target
EOF

print_green "Service file created at $SERVICE_FILE"

# Reload systemd and enable service
systemctl daemon-reload
systemctl enable soil-monitor.service

print_green "Systemd service enabled to start on boot"

# ========================
# SETUP LOG ROTATION
# ========================
print_green "[8/9] Setting up log rotation..."

# Create logrotate configuration
LOGROTATE_FILE="/etc/logrotate.d/soil-monitor"
tee $LOGROTATE_FILE > /dev/null << EOF
$DATA_DIR/*.log $LOG_DIR/*.log $GATEWAY_DATA_DIR/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 644 sensor sensor
    postrotate
        systemctl kill -s HUP soil-monitor.service 2>/dev/null || true
    endscript
}
EOF

print_green "Log rotation configured (keeps 14 days of logs)"

# ========================
# FINAL SETUP
# ========================
print_green "[9/9] Final setup steps..."

# Create example config if no config exists
CONFIG_FILE="$APP_DIR/Config.py"
if [ ! -f "$CONFIG_FILE" ]; then
    tee $CONFIG_FILE > /dev/null << 'EOF'
"""
CONFIGURATION FILE - UPDATE THESE IP ADDRESSES!
"""

import serial
import time
import pandas as pd
from datetime import datetime
import uuid
import sys

class Config:
    # ========================
    # NETWORK CONFIGURATION - UPDATE THESE!
    # ========================
    
    # Database Raspberry Pi (appV7.py server) - THIS MUST BE 192.168.1.95:5000
    DB_PI_URL = "http://192.168.1.95:5000"  # <-- appV7.py runs here
    
    # Gateway Raspberry Pi (for data forwarding) - UPDATE TO YOUR GATEWAY PI IP
    GATEWAY_PI_URL = "http://192.168.1.80:5000"  # <-- Your Gateway Pi IP
    
    # ========================
    # SENSOR HARDWARE CONFIG
    # ========================
    
    SERIAL_PORT = '/dev/ttyUSB0'  # Change if your sensor is on different port
    SERIAL_BAUDRATE = 9600
    SERIAL_TIMEOUT = 1
    RESPONSE_LENGTH = 19
    
    # Modbus command
    MODBUS_COMMAND = bytes([0x01, 0x03, 0x00, 0x00, 0x00, 0x07, 0x04, 0x08])
    
    # ========================
    # SYSTEM BEHAVIOR
    # ========================
    
    MEASUREMENT_INTERVAL = 300  # 5 minutes
    ASSIGNMENT_CHECK_INTERVAL = 14400  # 4 hours
    GATEWAY_CHECK_INTERVAL = 3600  # 1 hour
    MAX_RETRY_ATTEMPTS = 3
    RETRY_DELAY = 5
    
    # ========================
    # OFFLINE STORAGE
    # ========================
    
    OFFLINE_STORAGE = '/home/sensor/sensor_data/offline_data.csv'
    MAX_OFFLINE_RECORDS = 1000
    
    # ========================
    # LOGGING
    # ========================
    
    LOG_FILE = '/home/sensor/sensor_data/sensor_system.log'
    LOG_LEVEL = 'INFO'
EOF
    chown sensor:sensor $CONFIG_FILE
    print_green "Example Config.py created at $CONFIG_FILE"
fi

# ========================
# FIREWALL CONFIGURATION
# ========================
print_green "Configuring firewall..."
ufw allow 5000/tcp  # Allow Flask app port
ufw allow 22/tcp    # Allow SSH
ufw --force enable 2>/dev/null || true

# ========================
# INSTALLATION COMPLETE
# ========================
echo "================================================"
echo -e "${GREEN}✅ INSTALLATION COMPLETE!${NC}"
echo "================================================"
echo ""
echo "👤 USER ACCOUNT:"
echo "   Username: sensor"
echo "   Password: sensor123 (change with: sudo passwd sensor)"
echo "   Home directory: /home/sensor"
echo ""
echo "📋 NEXT STEPS:"
echo "1. Switch to sensor user: sudo su - sensor"
echo "2. Copy all Python files to: $APP_DIR"
echo "3. Edit Config.py with your actual IP addresses:"
echo "   - DB_PI_URL: Should be http://192.168.1.95:5000"
echo "   - GATEWAY_PI_URL: Your Gateway Pi IP (e.g., http://192.168.1.80:5000)"
echo "4. Check SERIAL_PORT in Config.py (/dev/ttyUSB0 or /dev/ttyACM0)"
echo ""
echo "🔧 SERVICE COMMANDS:"
echo "   sudo systemctl start soil-monitor     # Start now"
echo "   sudo systemctl stop soil-monitor      # Stop service"
echo "   sudo systemctl restart soil-monitor   # Restart service"
echo "   sudo systemctl status soil-monitor    # Check status"
echo "   journalctl -u soil-monitor -f         # View live logs"
echo ""
echo "📊 LOG FILES:"
echo "   $DATA_DIR/sensor_system.log      # Application logs"
echo "   $DATA_DIR/offline_data.csv       # Offline data storage"
echo ""
echo "🔍 TEST THE SYSTEM:"
echo "   1. Switch to sensor user: sudo su - sensor"
echo "   2. Navigate to app: cd $APP_DIR"
echo "   3. Run test: python3 test_connection.py"
echo "   4. Start service: sudo systemctl start soil-monitor"
echo "   5. Check logs: journalctl -u soil-monitor -f"
echo ""
echo "🔄 The system will automatically start on boot!"
echo "================================================"
echo "================================================"
