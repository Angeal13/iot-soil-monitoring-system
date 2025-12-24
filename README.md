# IoT Soil Sensor Node

Raspberry Pi-based soil monitoring sensor that collects data and sends to central gateway.

## Features
- Reads soil moisture, temperature, conductivity, pH, NPK
- Auto-registers with central system
- Checks assignment status before collecting data
- Stores data locally when offline
- Forwards to Gateway Pi when connected

## Quick Setup
1. Clone repository: `git clone https://github.com/yourname/iot-sensor-node.git`
2. Run installer: `sudo ./scripts/install.sh`
3. Edit Config.py with your IP addresses
4. Start service: `sudo systemctl start soil-monitor`

## Configuration
Edit `src/Config.py`:
```python
DB_PI_URL = "http://192.168.1.95:5000"      # appV7.py server
GATEWAY_PI_URL = "http://192.168.1.80:5000" # Gateway Pi
SERIAL_PORT = "/dev/ttyUSB0"                # Soil sensor port
