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
if [[ $EUID -eq 0 ]]; then
    print_yellow "Running as root - creating virtual environment as pi user"
    # Create virtual environment as pi user
    sudo -u pi python3 -m venv /home/pi/soil-sensor-venv 2>/dev/null || true
else
    # Create virtual environment
    python3 -m venv /home/pi/soil-sensor-venv 2>/dev/null || true
fi

# ========================
# SYSTEM UPDATE
# ========================
print_green "[1/8] Updating system packages..."
sudo apt update
sudo apt upgrade -y

# ========================
# INSTALL PYTHON & DEPENDENCIES
# ========================
print_green "[2/8] Installing Python and dependencies..."
sudo apt install python3 python3-pip python3-venv python3-pandas python3-serial -y

# ========================
# INSTALL PYTHON PACKAGES
# ========================
print_green "[3/8] Installing Python packages using system packages..."
# Install packages using apt to avoid pip system installation issues
sudo apt install python3-pandas python3-requests -y

# Install remaining packages using pip with user flag
if [[ $EUID -eq 0 ]]; then
    # If running as root, install as pi user
    sudo -u pi /home/pi/soil-sensor-venv/bin/pip install pyserial==3.5 requests==2.31.0 --no-warn-script-location
else
    # If running as pi user, use virtual environment
    /home/pi/soil-sensor-venv/bin/pip install pyserial==3.5 requests==2.31.0 --no-warn-script-location
fi

# ========================
# CREATE APPLICATION STRUCTURE
# ========================
print_green "[4/8] Setting up application directory structure..."

# Main application directory - UPDATED TO MATCH REPOSITORY NAME
APP_DIR="/home/pi/iot-soil-monitoring-system"
sudo mkdir -p $APP_DIR
sudo chown pi:pi $APP_DIR
sudo chmod 755 $APP_DIR

# Data storage directory
DATA_DIR="/home/pi/sensor_data"
sudo mkdir -p $DATA_DIR
sudo chown pi:pi $DATA_DIR
sudo chmod 755 $DATA_DIR

# Logs directory
LOG_DIR="/home/pi/sensor_logs"
sudo mkdir -p $LOG_DIR
sudo chown pi:pi $LOG_DIR
sudo chmod 755 $LOG_DIR

# Gateway data directory
GATEWAY_DATA_DIR="/home/pi/gateway_data"
sudo mkdir -p $GATEWAY_DATA_DIR
sudo chown pi:pi $GATEWAY_DATA_DIR
sudo chmod 755 $GATEWAY_DATA_DIR

print_green "Application directories created:"
print_green "  - $APP_DIR (Python code - matches repository name)"
print_green "  - $DATA_DIR (sensor data storage)"
print_green "  - $LOG_DIR (system logs)"
print_green "  - $GATEWAY_DATA_DIR (gateway offline storage)"

# ========================
# ENABLE SERIAL INTERFACE
# ========================
print_green "[5/8] Configuring serial interface..."

# Disable serial console but enable serial port hardware
sudo raspi-config nonint do_serial 2

# Add user to dialout group for serial access
sudo usermod -a -G dialout pi

# Set correct permissions for serial ports
sudo chmod 666 /dev/ttyUSB0 2>/dev/null || true
sudo chmod 666 /dev/ttyACM0 2>/dev/null || true

print_green "Serial interface configured"
print_green "User 'pi' added to dialout group"

# ========================
# SETUP AUTO-START SERVICE
# ========================
print_green "[6/8] Setting up auto-start service..."

# Create systemd service file
SERVICE_FILE="/etc/systemd/system/soil-monitor.service"

# Use virtual environment in service file if it exists
VENV_PATH="/home/pi/soil-sensor-venv"
if [ -d "$VENV_PATH" ]; then
    PYTHON_PATH="$VENV_PATH/bin/python3"
else
    PYTHON_PATH="/usr/bin/python3"
fi

sudo tee $SERVICE_FILE > /dev/null << EOF
[Unit]
Description=Soil Monitoring IoT System
After=network.target
Wants=network.target
StartLimitIntervalSec=500
StartLimitBurst=5

[Service]
Type=simple
User=pi
WorkingDirectory=$APP_DIR
ExecStart=$PYTHON_PATH $APP_DIR/MainController.py
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
sudo systemctl daemon-reload
sudo systemctl enable soil-monitor.service

print_green "Systemd service enabled to start on boot"

# ========================
# SETUP LOG ROTATION
# ========================
print_green "[7/8] Setting up log rotation..."

# Create logrotate configuration
LOGROTATE_FILE="/etc/logrotate.d/soil-monitor"
sudo tee $LOGROTATE_FILE > /dev/null << EOF
$DATA_DIR/*.log $LOG_DIR/*.log $GATEWAY_DATA_DIR/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 644 pi pi
    postrotate
        systemctl kill -s HUP soil-monitor.service 2>/dev/null || true
    endscript
}
EOF

print_green "Log rotation configured (keeps 14 days of logs)"

# ========================
# FINAL SETUP
# ========================
print_green "[8/8] Final setup steps..."

# Make Python scripts executable
if [ -d "$APP_DIR" ]; then
    chmod +x $APP_DIR/*.py
    print_green "Python scripts made executable"
else
    print_yellow "Warning: $APP_DIR doesn't exist yet - will be created when you copy files"
fi

# Create example config if no config exists
CONFIG_FILE="$APP_DIR/Config.py"
if [ ! -f "$CONFIG_FILE" ]; then
    sudo tee $CONFIG_FILE > /dev/null << 'EOF'
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
    
    OFFLINE_STORAGE = '/home/pi/sensor_data/offline_data.csv'
    MAX_OFFLINE_RECORDS = 1000
    
    # ========================
    # LOGGING
    # ========================
    
    LOG_FILE = '/home/pi/sensor_data/sensor_system.log'
    LOG_LEVEL = 'INFO'
EOF
    print_green "Example Config.py created at $CONFIG_FILE"
fi

# ========================
# FIREWALL CONFIGURATION
# ========================
print_green "Configuring firewall..."
sudo ufw allow 5000/tcp  # Allow Flask app port
sudo ufw allow 22/tcp    # Allow SSH
sudo ufw --force enable 2>/dev/null || true

# ========================
# INSTALLATION COMPLETE
# ========================
echo "================================================"
echo -e "${GREEN}✅ INSTALLATION COMPLETE!${NC}"
echo "================================================"
echo ""
echo "📋 NEXT STEPS:"
echo "1. Copy all Python files to: $APP_DIR"
echo "2. Edit Config.py with your actual IP addresses:"
echo "   - DB_PI_URL: Should be http://192.168.1.95:5000"
echo "   - GATEWAY_PI_URL: Your Gateway Pi IP (e.g., http://192.168.1.80:5000)"
echo "3. Check SERIAL_PORT in Config.py (/dev/ttyUSB0 or /dev/ttyACM0)"
echo ""
echo "🔧 SERVICE COMMANDS:"
echo "   sudo systemctl start soil-monitor     # Start now"
echo "   sudo systemctl stop soil-monitor      # Stop service"
echo "   sudo systemctl restart soil-monitor   # Restart service"
echo "   sudo systemctl status soil-monitor    # Check status"
echo "   journalctl -u soil-monitor -f         # View live logs"
echo ""
echo "🐍 PYTHON ENVIRONMENT:"
if [ -d "$VENV_PATH" ]; then
    echo "   Virtual environment created at: $VENV_PATH"
    echo "   To activate: source $VENV_PATH/bin/activate"
else
    echo "   Using system Python: /usr/bin/python3"
fi
echo ""
echo "📊 LOG FILES:"
echo "   $DATA_DIR/sensor_system.log      # Application logs"
echo "   $DATA_DIR/offline_data.csv       # Offline data storage"
echo "   $GATEWAY_DATA_DIR/gateway.log    # Gateway logs"
echo ""
echo "🔍 TEST THE SYSTEM:"
echo "   1. Start service: sudo systemctl start soil-monitor"
echo "   2. Check logs: journalctl -u soil-monitor -f"
echo "   3. Run test: python3 $APP_DIR/test_connection.py"
echo ""
echo "🔄 The system will automatically start on boot!"
echo "================================================"
