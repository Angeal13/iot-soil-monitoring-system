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
# SYSTEM UPDATE
# ========================
print_green "[1/8] Updating system packages..."
sudo apt update
sudo apt upgrade -y

# ========================
# INSTALL SYSTEM PACKAGES
# ========================
print_green "[2/8] Installing system packages..."
sudo apt install python3 python3-pip python3-venv -y

# Install pandas from apt (system package)
sudo apt install python3-pandas python3-numpy -y

# ========================
# CREATE VIRTUAL ENVIRONMENT
# ========================
print_green "[3/8] Creating virtual environment..."

# Remove old virtual environment if exists
sudo rm -rf /home/pi/soil-venv

# Create new virtual environment with access to system packages
sudo -u pi python3 -m venv /home/pi/soil-venv --system-site-packages

# ========================
# INSTALL PIP PACKAGES
# ========================
print_green "[4/8] Installing Python packages..."

# Upgrade pip first
sudo -u pi /home/pi/soil-venv/bin/pip install --upgrade pip

# Install required packages
sudo -u pi /home/pi/soil-venv/bin/pip install pyserial requests

# Verify installations
echo "Checking installations:"
sudo -u pi /home/pi/soil-venv/bin/python -c "import pandas; print('✅ pandas:', pandas.__version__)" || echo "❌ pandas not found"
sudo -u pi /home/pi/soil-venv/bin/python -c "import serial; print('✅ pyserial:', serial.VERSION)" || echo "❌ pyserial not found"
sudo -u pi /home/pi/soil-venv/bin/python -c "import requests; print('✅ requests:', requests.__version__)" || echo "❌ requests not found"

# ========================
# CREATE APPLICATION STRUCTURE
# ========================
print_green "[5/8] Setting up application directories..."

APP_DIR="/home/pi/iot-soil-monitoring-system"
sudo mkdir -p $APP_DIR
sudo chown pi:pi $APP_DIR
sudo chmod 755 $APP_DIR

DATA_DIR="/home/pi/sensor_data"
sudo mkdir -p $DATA_DIR
sudo chown pi:pi $DATA_DIR
sudo chmod 755 $DATA_DIR

print_green "Directories created:"
print_green "  - $APP_DIR"
print_green "  - $DATA_DIR"

# ========================
# FIX SERVICE FILE
# ========================
print_green "[6/8] Configuring service..."

# Create or update service file
sudo tee /etc/systemd/system/soil-monitor.service > /dev/null << EOF
[Unit]
Description=Soil Monitoring IoT System
After=network.target
Wants=network.target

[Service]
Type=simple
User=pi
Group=pi
WorkingDirectory=/home/pi/iot-soil-monitoring-system

# Use virtual environment Python
ExecStart=/home/pi/soil-venv/bin/python /home/pi/iot-soil-monitoring-system/MainController.py

# Restart on failure
Restart=always
RestartSec=10

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=soil-monitor

# Environment
Environment=PYTHONUNBUFFERED=1
Environment=PYTHONPATH=/home/pi/iot-soil-monitoring-system

# Security
NoNewPrivileges=true
PrivateTmp=true
ReadWritePaths=/home/pi/sensor_data

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd
sudo systemctl daemon-reload

# ========================
# CREATE TEST SCRIPT
# ========================
print_green "[7/8] Creating test script..."

sudo tee /home/pi/test_installation.py > /dev/null << 'EOF'
#!/usr/bin/env python3
"""
Test installation script
"""

import sys
import subprocess

print("=" * 60)
print("Testing IoT Soil Monitoring Installation")
print("=" * 60)

# Test 1: Check Python version in venv
print("\n1. Testing virtual environment Python:")
result = subprocess.run(['/home/pi/soil-venv/bin/python', '--version'], 
                       capture_output=True, text=True)
print(f"   Python: {result.stdout.strip()}")

# Test 2: Check imports in virtual environment
print("\n2. Testing module imports in virtual environment:")

test_script = """
import sys
print(f"Python path: {sys.executable}")

try:
    import pandas
    print(f"✅ pandas {pandas.__version__}")
except ImportError as e:
    print(f"❌ pandas: {e}")

try:
    import serial
    print(f"✅ pyserial {serial.VERSION}")
except ImportError as e:
    print(f"❌ pyserial: {e}")

try:
    import requests
    print(f"✅ requests {requests.__version__}")
except ImportError as e:
    print(f"❌ requests: {e}")

try:
    import numpy
    print(f"✅ numpy {numpy.__version__}")
except ImportError as e:
    print(f"❌ numpy: {e}")
"""

# Write test to temp file
with open('/tmp/test_imports.py', 'w') as f:
    f.write(test_script)

# Run test in virtual environment
result = subprocess.run(['/home/pi/soil-venv/bin/python', '/tmp/test_imports.py'],
                       capture_output=True, text=True)
print(result.stdout)

# Test 3: Check service
print("\n3. Checking service configuration:")
result = subprocess.run(['systemctl', 'status', 'soil-monitor'], 
                       capture_output=True, text=True)
if 'Loaded: loaded' in result.stdout:
    print("   ✅ Service file loaded")
else:
    print("   ⚠️ Service file not loaded")

print("\n" + "=" * 60)
print("Test complete")
print("=" * 60)

# Instructions
print("\n📋 If pandas is missing, run:")
print("   sudo apt install python3-pandas python3-numpy")
print("   sudo -u pi /home/pi/soil-venv/bin/pip install --upgrade pip")
print("\n🚀 To test the system:")
print("   cd /home/pi/iot-soil-monitoring-system")
print("   /home/pi/soil-venv/bin/python MainController.py")
EOF

sudo chown pi:pi /home/pi/test_installation.py
sudo chmod +x /home/pi/test_installation.py

# ========================
# FINAL CHECKS
# ========================
print_green "[8/8] Running final checks..."

# Set proper permissions
sudo chown -R pi:pi /home/pi/soil-venv
sudo chown -R pi:pi /home/pi/iot-soil-monitoring-system 2>/dev/null || true

# Test the installation
echo "Running installation test..."
sudo -u pi python3 /home/pi/test_installation.py

# ========================
# INSTALLATION COMPLETE
# ========================
echo "================================================"
echo -e "${GREEN}✅ INSTALLATION COMPLETE!${NC}"
echo "================================================"
echo ""
echo "🔧 IF PANDAS IS STILL MISSING, RUN THESE COMMANDS:"
echo ""
echo "1. Install system pandas:"
echo "   sudo apt install python3-pandas python3-numpy"
echo ""
echo "2. Recreate virtual environment:"
echo "   sudo rm -rf /home/pi/soil-venv"
echo "   sudo -u pi python3 -m venv /home/pi/soil-venv --system-site-packages"
echo ""
echo "3. Install pip packages:"
echo "   sudo -u pi /home/pi/soil-venv/bin/pip install --upgrade pip"
echo "   sudo -u pi /home/pi/soil-venv/bin/pip install pyserial requests"
echo ""
echo "4. Test imports:"
echo "   /home/pi/soil-venv/bin/python -c \"import pandas; print('pandas:', pandas.__version__)\""
echo ""
echo "🚀 TO DEPLOY YOUR CODE:"
echo "1. Copy all your Python files to:"
echo "   /home/pi/iot-soil-monitoring-system/"
echo ""
echo "2. Test manually:"
echo "   cd /home/pi/iot-soil-monitoring-system"
echo "   /home/pi/soil-venv/bin/python MainController.py"
echo ""
echo "3. Start the service:"
echo "   sudo systemctl start soil-monitor"
echo "   sudo systemctl status soil-monitor"
echo ""
echo "📊 VIEW LOGS:"
echo "   sudo journalctl -u soil-monitor -f"
echo "================================================"
# 6. Reload and test
sudo systemctl daemon-reload
cd /home/pi/iot-soil-monitoring-system
/home/pi/soil-venv/bin/python MainController.py
