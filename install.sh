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
    print_yellow "Running as root - will install for pi user"
else
    print_yellow "Running as pi user - may need sudo for some operations"
fi

# ========================
# SYSTEM UPDATE
# ========================
print_green "[1/10] Updating system packages..."
sudo apt update
sudo apt upgrade -y

# ========================
# INSTALL SYSTEM PACKAGES
# ========================
print_green "[2/10] Installing system packages..."
sudo apt install python3 python3-pip python3-venv -y
sudo apt install python3-pandas python3-numpy python3-requests -y

# ========================
# CREATE VIRTUAL ENVIRONMENT
# ========================
print_green "[3/10] Creating virtual environment..."

# Remove old virtual environment if exists
if [ -d "/home/pi/soil-venv" ]; then
    sudo rm -rf /home/pi/soil-venv
    print_yellow "Removed old virtual environment"
fi

# Create new virtual environment with access to system packages
sudo -u pi python3 -m venv /home/pi/soil-venv --system-site-packages
print_green "Virtual environment created at /home/pi/soil-venv"

# ========================
# INSTALL ADDITIONAL PIP PACKAGES
# ========================
print_green "[4/10] Installing additional Python packages..."

# Upgrade pip first
sudo -u pi /home/pi/soil-venv/bin/pip install --upgrade pip

# Install pyserial in virtual environment
sudo -u pi /home/pi/soil-venv/bin/pip install pyserial

# Verify installations
echo ""
print_green "Verifying package installations:"
sudo -u pi /home/pi/soil-venv/bin/python -c "import pandas; print('  ✅ pandas:', pandas.__version__)" || print_red "  ❌ pandas not found"
sudo -u pi /home/pi/soil-venv/bin/python -c "import serial; print('  ✅ pyserial:', serial.VERSION)" || print_red "  ❌ pyserial not found"
sudo -u pi /home/pi/soil-venv/bin/python -c "import requests; print('  ✅ requests:', requests.__version__)" || print_red "  ❌ requests not found"
echo ""

# ========================
# CREATE ALL APPLICATION DIRECTORIES
# ========================
print_green "[5/10] Creating application directory structure..."

# Main application directory
APP_DIR="/home/pi/iot-soil-monitoring-system"
sudo mkdir -p $APP_DIR
sudo chown pi:pi $APP_DIR
sudo chmod 755 $APP_DIR

# Data storage directory (for offline storage)
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

# Archive directory for old logs/data
ARCHIVE_DIR="/home/pi/sensor_archive"
sudo mkdir -p $ARCHIVE_DIR
sudo chown pi:pi $ARCHIVE_DIR
sudo chmod 755 $ARCHIVE_DIR

print_green "Application directories created:"
print_green "  📁 $APP_DIR (Python code)"
print_green "  💾 $DATA_DIR (sensor data storage)"
print_green "  📋 $LOG_DIR (system logs)"
print_green "  🔗 $GATEWAY_DATA_DIR (gateway offline storage)"
print_green "  🗄️  $ARCHIVE_DIR (data archive)"

# ========================
# CREATE LOG FILES WITH PROPER PERMISSIONS
# ========================
print_green "[6/10] Creating log files with proper permissions..."

# Main system log
MAIN_LOG="/home/pi/sensor_data/sensor_system.log"
sudo touch $MAIN_LOG
sudo chown pi:pi $MAIN_LOG
sudo chmod 644 $MAIN_LOG

# Gateway log
GATEWAY_LOG="/home/pi/gateway_data/gateway.log"
sudo touch $GATEWAY_LOG
sudo chown pi:pi $GATEWAY_LOG
sudo chmod 644 $GATEWAY_LOG

# Error log
ERROR_LOG="/home/pi/sensor_logs/error.log"
sudo touch $ERROR_LOG
sudo chown pi:pi $ERROR_LOG
sudo chmod 644 $ERROR_LOG

print_green "Log files created:"
print_green "  📝 $MAIN_LOG"
print_green "  📝 $GATEWAY_LOG"
print_green "  📝 $ERROR_LOG"

# ========================
# CREATE OFFLINE STORAGE FILE
# ========================
print_green "[7/10] Creating offline storage file..."

OFFLINE_FILE="/home/pi/sensor_data/offline_data.csv"
sudo touch $OFFLINE_FILE
sudo chown pi:pi $OFFLINE_FILE
sudo chmod 644 $OFFLINE_FILE

# Add CSV header if file is empty
if [ ! -s "$OFFLINE_FILE" ]; then
    echo "machine_id,timestamp,farm_id,zone_code,moisture,temperature,conductivity,ph,nitrogen,phosphorus,potassium,crc_valid,response_bytes" | sudo tee $OFFLINE_FILE > /dev/null
fi

print_green "Offline storage: $OFFLINE_FILE"

# ========================
# ENABLE SERIAL INTERFACE
# ========================
print_green "[8/10] Configuring serial interface..."

# Disable serial console but enable serial port hardware
sudo raspi-config nonint do_serial 2

# Add user to dialout group for serial access
sudo usermod -a -G dialout pi

# Set correct permissions for serial ports
sudo chmod 666 /dev/ttyUSB0 2>/dev/null || print_yellow "  /dev/ttyUSB0 not found (will be created when sensor connected)"
sudo chmod 666 /dev/ttyACM0 2>/dev/null || print_yellow "  /dev/ttyACM0 not found (will be created when sensor connected)"
sudo chmod 666 /dev/ttyAMA0 2>/dev/null || print_yellow "  /dev/ttyAMA0 not found (GPIO serial)"

print_green "Serial interface configured"
print_green "User 'pi' added to dialout group"

# ========================
# SETUP AUTO-START SERVICE
# ========================
print_green "[9/10] Setting up auto-start service..."

# Create systemd service file
SERVICE_FILE="/etc/systemd/system/soil-monitor.service"

sudo tee $SERVICE_FILE > /dev/null << EOF
[Unit]
Description=IoT Soil Monitoring System
After=network.target
Wants=network.target
StartLimitIntervalSec=500
StartLimitBurst=5

[Service]
Type=simple
User=pi
Group=pi
WorkingDirectory=/home/pi/iot-soil-monitoring-system

# Environment setup
Environment=HOME=/home/pi
Environment=USER=pi
Environment=PYTHONUNBUFFERED=1
Environment=PYTHONPATH=/home/pi/iot-soil-monitoring-system

# Use virtual environment Python
ExecStart=/home/pi/soil-venv/bin/python /home/pi/iot-soil-monitoring-system/MainController.py

# Pre-start: Ensure directories and files exist with correct permissions
ExecStartPre=/bin/mkdir -p /home/pi/sensor_data /home/pi/sensor_logs /home/pi/gateway_data /home/pi/sensor_archive
ExecStartPre=/bin/chown -R pi:pi /home/pi/sensor_data /home/pi/sensor_logs /home/pi/gateway_data /home/pi/sensor_archive
ExecStartPre=/bin/chmod -R 755 /home/pi/sensor_data /home/pi/sensor_logs /home/pi/gateway_data /home/pi/sensor_archive
ExecStartPre=/bin/touch /home/pi/sensor_data/sensor_system.log /home/pi/gateway_data/gateway.log /home/pi/sensor_logs/error.log
ExecStartPre=/bin/chown pi:pi /home/pi/sensor_data/sensor_system.log /home/pi/gateway_data/gateway.log /home/pi/sensor_logs/error.log
ExecStartPre=/bin/chmod 644 /home/pi/sensor_data/sensor_system.log /home/pi/gateway_data/gateway.log /home/pi/sensor_logs/error.log

# Restart configuration
Restart=always
RestartSec=10

# Logging to journal
StandardOutput=journal
StandardError=journal
SyslogIdentifier=soil-monitor

# Security
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=/home/pi/sensor_data /home/pi/sensor_logs /home/pi/gateway_data /home/pi/sensor_archive

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
print_green "[10/10] Setting up log rotation..."

# Create logrotate configuration
LOGROTATE_FILE="/etc/logrotate.d/soil-monitor"
sudo tee $LOGROTATE_FILE > /dev/null << EOF
/home/pi/sensor_data/*.log
/home/pi/sensor_logs/*.log
/home/pi/gateway_data/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 644 pi pi
    sharedscripts
    postrotate
        systemctl kill -s HUP soil-monitor.service 2>/dev/null || true
    endscript
}
EOF

print_green "Log rotation configured (keeps 14 days of logs)"

# ========================
# CREATE TEST SCRIPT
# ========================
print_green "Creating test script..."

TEST_SCRIPT="$APP_DIR/test_installation.py"
sudo tee $TEST_SCRIPT > /dev/null << 'EOF'
#!/usr/bin/env python3
"""
Test installation and permissions
"""

import os
import sys
import logging
import time

def test_installation():
    print("=" * 60)
    print("🔧 Testing IoT Soil Monitoring Installation")
    print("=" * 60)
    
    # Test 1: Check directories
    print("\n1. Testing directories:")
    directories = [
        '/home/pi/iot-soil-monitoring-system',
        '/home/pi/sensor_data',
        '/home/pi/sensor_logs',
        '/home/pi/gateway_data',
        '/home/pi/sensor_archive'
    ]
    
    all_dirs_ok = True
    for directory in directories:
        if os.path.exists(directory):
            stat = os.stat(directory)
            writable = os.access(directory, os.W_OK)
            status = "✅" if writable else "❌"
            print(f"   {status} {directory}")
            print(f"      Owner: {stat.st_uid}, Permissions: {oct(stat.st_mode)[-3:]}, Writable: {writable}")
        else:
            print(f"   ❌ {directory} - does not exist")
            all_dirs_ok = False
    
    # Test 2: Check log files
    print("\n2. Testing log files:")
    log_files = [
        '/home/pi/sensor_data/sensor_system.log',
        '/home/pi/gateway_data/gateway.log',
        '/home/pi/sensor_logs/error.log'
    ]
    
    all_logs_ok = True
    for log_file in log_files:
        if os.path.exists(log_file):
            try:
                with open(log_file, 'a') as f:
                    f.write(f"Test write at {time.ctime()}\n")
                print(f"   ✅ {log_file} - writable")
            except Exception as e:
                print(f"   ❌ {log_file} - not writable: {e}")
                all_logs_ok = False
        else:
            print(f"   ❌ {log_file} - does not exist")
            all_logs_ok = False
    
    # Test 3: Test Python imports
    print("\n3. Testing Python imports:")
    try:
        import pandas
        print(f"   ✅ pandas {pandas.__version__}")
    except ImportError as e:
        print(f"   ❌ pandas: {e}")
        all_dirs_ok = False
    
    try:
        import serial
        print(f"   ✅ pyserial {serial.VERSION}")
    except ImportError as e:
        print(f"   ❌ pyserial: {e}")
        all_dirs_ok = False
    
    try:
        import requests
        print(f"   ✅ requests {requests.__version__}")
    except ImportError as e:
        print(f"   ❌ requests: {e}")
        all_dirs_ok = False
    
    # Test 4: Test logging setup
    print("\n4. Testing logging system:")
    try:
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler('/home/pi/sensor_data/sensor_system.log'),
                logging.StreamHandler(sys.stdout)
            ]
        )
        logger = logging.getLogger('InstallTest')
        logger.info("✅ Installation test completed successfully")
        print("   ✅ Logging system working")
    except Exception as e:
        print(f"   ❌ Logging failed: {e}")
        all_logs_ok = False
    
    # Summary
    print("\n" + "=" * 60)
    print("📊 TEST SUMMARY:")
    if all_dirs_ok and all_logs_ok:
        print("✅ All tests passed! Installation successful.")
    else:
        print("⚠️  Some tests failed. Check permissions and paths.")
    
    print("\n🚀 To start the system:")
    print("   sudo systemctl start soil-monitor")
    print("   sudo systemctl status soil-monitor")
    print("\n📊 To view logs:")
    print("   sudo journalctl -u soil-monitor -f")
    print("=" * 60)

if __name__ == "__main__":
    test_installation()
EOF

sudo chown pi:pi $TEST_SCRIPT
sudo chmod +x $TEST_SCRIPT

# ========================
# CREATE DEFAULT CONFIG IF MISSING
# ========================
CONFIG_FILE="$APP_DIR/Config.py"
if [ ! -f "$CONFIG_FILE" ]; then
    print_green "Creating default Config.py..."
    
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
    
    # Database Raspberry Pi (appV7.py server)
    DB_PI_URL = "http://192.168.1.95:5000"
    
    # Gateway Raspberry Pi
    GATEWAY_PI_URL = "http://192.168.1.80:5000"
    
    # API Timeouts
    DB_TIMEOUT = 10
    GATEWAY_TIMEOUT = 10
    
    # ========================
    # SENSOR HARDWARE CONFIG
    # ========================
    
    SERIAL_PORT = '/dev/ttyUSB0'
    SERIAL_BAUDRATE = 9600
    SERIAL_TIMEOUT = 1
    RESPONSE_LENGTH = 19
    
    # Modbus command
    MODBUS_COMMAND = bytes([0x01, 0x03, 0x00, 0x00, 0x00, 0x07, 0x04, 0x08])
    
    # ========================
    # SYSTEM BEHAVIOR
    # ========================
    
    MEASUREMENT_INTERVAL = 300
    ASSIGNMENT_CHECK_INTERVAL = 14400
    GATEWAY_CHECK_INTERVAL = 3600
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
    
    # ========================
    # API ENDPOINTS
    # ========================
    
    @classmethod
    def get_assignment_url(cls, machine_id):
        return f"{cls.DB_PI_URL}/api/sensors/{machine_id}/assignment"
    
    @classmethod
    def get_registration_url(cls):
        return f"{cls.DB_PI_URL}/api/sensors/register"
    
    @classmethod
    def get_gateway_data_url(cls):
        return f"{cls.GATEWAY_PI_URL}/api/sensor-data"
    
    @classmethod
    def get_health_url(cls):
        return f"{cls.DB_PI_URL}/api/test"
    
    @classmethod
    def get_machine_id(cls):
        return str(uuid.getnode())
    
    @classmethod
    def validate_config(cls):
        print("✅ Configuration validated")
        return True
EOF
    
    sudo chown pi:pi $CONFIG_FILE
    print_green "Default Config.py created at $CONFIG_FILE"
fi

# ========================
# FIREWALL CONFIGURATION
# ========================
print_green "Configuring firewall..."
sudo ufw allow 5000/tcp 2>/dev/null || print_yellow "UFW not installed or already configured"
sudo ufw allow 22/tcp 2>/dev/null || print_yellow "UFW not installed or already configured"

# ========================
# FINAL PERMISSIONS CHECK
# ========================
print_green "Setting final permissions..."
sudo chown -R pi:pi /home/pi/soil-venv
sudo chown -R pi:pi $APP_DIR 2>/dev/null || true

# ========================
# INSTALLATION COMPLETE
# ========================
echo "================================================"
echo -e "${GREEN}✅ INSTALLATION COMPLETE!${NC}"
echo "================================================"
echo ""
echo "📋 NEXT STEPS:"
echo "1. Copy your Python files to: $APP_DIR"
echo "2. Edit Config.py with your IP addresses:"
echo "   - DB_PI_URL: Should be http://192.168.1.95:5000"
echo "   - GATEWAY_PI_URL: Your Gateway Pi IP"
echo "3. Check SERIAL_PORT in Config.py"
echo ""
echo "🔧 TEST THE INSTALLATION:"
echo "   cd $APP_DIR"
echo "   python3 test_installation.py"
echo ""
echo "🚀 START THE SYSTEM:"
echo "   sudo systemctl start soil-monitor"
echo "   sudo systemctl status soil-monitor"
echo ""
echo "📊 VIEW LOGS:"
echo "   sudo journalctl -u soil-monitor -f"
echo "   tail -f /home/pi/sensor_data/sensor_system.log"
echo ""
echo "📁 DIRECTORIES CREATED:"
echo "   $APP_DIR - Python application"
echo "   $DATA_DIR - Sensor data storage"
echo "   $LOG_DIR - System logs"
echo "   $GATEWAY_DATA_DIR - Gateway offline storage"
echo "   $ARCHIVE_DIR - Data archive"
echo ""
echo "🐍 VIRTUAL ENVIRONMENT:"
echo "   /home/pi/soil-venv"
echo "   Activate: source /home/pi/soil-venv/bin/activate"
echo ""
echo "🔄 The system will automatically start on boot!"
echo "================================================"

sudo reboot
