"""
Sensor Reader Module
Handles communication with soil sensor hardware
"""

import serial
import time
from datetime import datetime
import uuid
from Config import Config
import logging
import requests
import sys

class SensorReader:
    def __init__(self):
        self.machine_id = Config.get_machine_id()
        self.serial_conn = None
        self.is_assigned = False
        self.assigned_farm_id = None
        self.assigned_zone_code = None
        self.last_assignment_check = 0
        self.sensor_type = "Soil_Monitor_V1"
        self.firmware_version = "1.0"
        
        # Setup logging
        self.setup_logging()
        
        logging.info("=" * 50)
        logging.info(f"🌱 Soil Sensor IoT System Starting")
        logging.info(f"📟 Machine ID: {self.machine_id}")
        logging.info(f"🔗 DB Pi URL: {Config.DB_PI_URL}")  # Should show 192.168.1.95
        logging.info(f"🔗 Gateway Pi URL: {Config.GATEWAY_PI_URL}")
        logging.info(f"📏 Response Length: {Config.RESPONSE_LENGTH} bytes")
        logging.info("=" * 50)
        
        # Initialize serial connection
        self.initialize_serial()
        
        # Register sensor on startup
        self.register_sensor()
        
        # Check initial assignment
        self.check_assignment_status(force=True)
    
    def setup_logging(self):
        """Configure logging system"""
        logging.basicConfig(
            level=getattr(logging, Config.LOG_LEVEL),
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(Config.LOG_FILE),
                logging.StreamHandler(sys.stdout)
            ]
        )
    
    def initialize_serial(self):
        """Initialize serial connection with retry logic"""
        logging.info(f"🔌 Initializing serial connection to {Config.SERIAL_PORT}")
        
        for attempt in range(Config.MAX_RETRY_ATTEMPTS):
            try:
                self.serial_conn = serial.Serial(
                    port=Config.SERIAL_PORT,
                    baudrate=Config.SERIAL_BAUDRATE,
                    timeout=Config.SERIAL_TIMEOUT,
                    bytesize=serial.EIGHTBITS,
                    parity=serial.PARITY_NONE,
                    stopbits=serial.STOPBITS_ONE
                )
                
                # Test connection
                if self.serial_conn.is_open:
                    logging.info(f"✅ Serial connected to {Config.SERIAL_PORT} at {Config.SERIAL_BAUDRATE} baud")
                    return True
                else:
                    logging.warning(f"Serial port {Config.SERIAL_PORT} not open")
                    
            except serial.SerialException as e:
                logging.warning(f"Serial attempt {attempt + 1}/{Config.MAX_RETRY_ATTEMPTS} failed: {e}")
                
                if attempt < Config.MAX_RETRY_ATTEMPTS - 1:
                    time.sleep(Config.RETRY_DELAY)
                else:
                    logging.error(f"❌ Failed to initialize serial connection after {Config.MAX_RETRY_ATTEMPTS} attempts")
                    self.serial_conn = None
                    return False
        
        return False
    
    def _crc16_modbus(self, data):
        """Calculate CRC16-Modbus checksum for a byte string (Little-Endian)"""
        crc = 0xFFFF
        for byte in data:
            crc ^= byte
            for _ in range(8):
                if crc & 0x0001:
                    crc >>= 1
                    crc ^= 0xA001
                else:
                    crc >>= 1
        return crc.to_bytes(2, byteorder='little')
    
    def register_sensor(self):
        """Register sensor with the central system (appV7.py)"""
        logging.info(f"📝 Registering sensor {self.machine_id}")
        
        sensor_info = {
            'machine_id': self.machine_id,
            'connection_timestamp': datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            'sensor_type': self.sensor_type,
            'firmware_version': self.firmware_version,
            'response_length': Config.RESPONSE_LENGTH
        }
        
        try:
            # First try through Gateway
            response = requests.post(
                f"{Config.GATEWAY_PI_URL}/api/sensors/register",
                json=sensor_info,
                timeout=Config.GATEWAY_TIMEOUT
            )
            
            if response.status_code in [200, 201]:
                data = response.json()
                logging.info(f"✅ Sensor registered via Gateway: {data.get('message')}")
                return True
            else:
                logging.warning(f"Gateway registration failed, trying direct DB connection")
                # Fallback to direct DB connection
                response = requests.post(
                    Config.get_registration_url(),
                    json=sensor_info,
                    timeout=Config.DB_TIMEOUT
                )
                
                if response.status_code in [200, 201]:
                    data = response.json()
                    logging.info(f"✅ Sensor registered via direct DB: {data.get('message')}")
                    return True
                else:
                    logging.warning(f"Direct registration failed with status {response.status_code}")
                    return False
                
        except requests.exceptions.RequestException as e:
            logging.error(f"❌ Registration failed: {e}")
            return False
    
    def check_assignment_status(self, force=False):
        """Check if sensor is assigned to a farm/zone via API"""
        current_time = time.time()
        
        # Check if enough time has passed since last check
        if not force and (current_time - self.last_assignment_check < Config.ASSIGNMENT_CHECK_INTERVAL):
            return self.is_assigned
        
        logging.info(f"🔍 Checking assignment status for sensor {self.machine_id}")
        
        try:
            # First try through Gateway Pi
            response = requests.get(
                f"{Config.GATEWAY_PI_URL}/api/sensors/{self.machine_id}/assignment",
                timeout=Config.GATEWAY_TIMEOUT
            )
            
            if response.status_code == 200:
                data = response.json()
                self.handle_assignment_response(data)
                self.last_assignment_check = current_time
                return self.is_assigned
            else:
                logging.warning(f"Gateway assignment check failed ({response.status_code}), trying direct DB")
                
        except requests.exceptions.RequestException as gateway_error:
            logging.warning(f"Gateway assignment check failed: {gateway_error}")
        
        # Fallback to direct DB Pi connection
        try:
            response = requests.get(
                Config.get_assignment_url(self.machine_id),
                timeout=Config.DB_TIMEOUT
            )
            
            if response.status_code == 200:
                data = response.json()
                self.handle_assignment_response(data)
                self.last_assignment_check = current_time
                return self.is_assigned
            elif response.status_code == 404:
                logging.warning(f"⚠️ Sensor {self.machine_id} not found in system")
                self.is_assigned = False
                self.last_assignment_check = current_time
                return False
            else:
                logging.warning(f"⚠️ DB Pi assignment check returned status {response.status_code}")
                return self.is_assigned  # Maintain current state on API failure
                
        except requests.exceptions.ConnectionError:
            logging.error(f"🔌 Cannot connect to DB Pi at {Config.DB_PI_URL}")
            return self.is_assigned  # Maintain current state
            
        except requests.exceptions.Timeout:
            logging.error("⏰ Assignment check timeout")
            return self.is_assigned  # Maintain current state
            
        except Exception as e:
            logging.error(f"❌ Assignment check failed: {e}")
            return self.is_assigned  # Maintain current state
    
    def handle_assignment_response(self, data):
        """Handle assignment response from API"""
        if 'assigned' in data:
            self.is_assigned = data['assigned']
            
            if self.is_assigned:
                self.assigned_farm_id = data.get('farm_id')
                self.assigned_zone_code = data.get('zone_code')
                logging.info(f"✅ Sensor assigned to Farm: {self.assigned_farm_id}, Zone: {self.assigned_zone_code}")
            else:
                self.assigned_farm_id = None
                self.assigned_zone_code = None
                logging.info("📭 Sensor not assigned to any farm")
    
    def read_sensor_data(self):
        """Read and parse data from soil sensor"""
        if not self.check_assignment_status():
            logging.warning("⏸️ Sensor not assigned - skipping data collection")
            return None
        
        if not self.serial_conn:
            if not self.initialize_serial():
                logging.error("❌ No serial connection available")
                return None
        
        try:
            # Send Modbus command
            self.serial_conn.write(Config.MODBUS_COMMAND)
            
            # Read response
            response = self.serial_conn.read(Config.RESPONSE_LENGTH)
            
            # Check response length
            if len(response) != Config.RESPONSE_LENGTH:
                logging.warning(f"📏 Response length mismatch. Expected {Config.RESPONSE_LENGTH}, got {len(response)}")
                
                # Try to read more data
                if len(response) < Config.RESPONSE_LENGTH:
                    remaining = Config.RESPONSE_LENGTH - len(response)
                    additional = self.serial_conn.read(remaining)
                    response += additional
                    logging.info(f"📥 Read additional {len(additional)} bytes")
                
                if len(response) != Config.RESPONSE_LENGTH:
                    return None
            
            # CRC Check
            expected_crc = response[-2:]
            data_to_check = response[:-2]
            calculated_crc = self._crc16_modbus(data_to_check)
            
            if expected_crc != calculated_crc:
                logging.warning("❌ CRC check failed. Data rejected.")
                return None
            
            # Parse sensor data
            sensor_data = {
                'machine_id': self.machine_id,
                'timestamp': datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                'farm_id': self.assigned_farm_id,
                'zone_code': self.assigned_zone_code,
                'moisture': int.from_bytes(response[3:5], 'big') / 10,
                'temperature': int.from_bytes(response[5:7], 'big') / 10,
                'conductivity': int.from_bytes(response[7:9], 'big') / 10,
                'ph': int.from_bytes(response[9:11], 'big') / 10,
                'nitrogen': int.from_bytes(response[11:13], 'big') / 10,
                'phosphorus': int.from_bytes(response[13:15], 'big') / 10,
                'potassium': int.from_bytes(response[15:17], 'big') / 10,
                'crc_valid': True,
                'response_bytes': len(response)
            }
            
            logging.info(f"📊 Sensor data collected: Moisture={sensor_data['moisture']}%, Temp={sensor_data['temperature']}°C")
            return sensor_data
            
        except serial.SerialException as e:
            logging.error(f"🔌 Serial error: {e}")
            self.serial_conn = None  # Reset connection
            return None
            
        except Exception as e:
            logging.error(f"❌ Error reading sensor data: {e}")
            return None
    
    def get_sensor_info(self):
        """Get sensor information for diagnostics"""
        return {
            'machine_id': self.machine_id,
            'sensor_type': self.sensor_type,
            'firmware_version': self.firmware_version,
            'is_assigned': self.is_assigned,
            'assigned_farm': self.assigned_farm_id,
            'assigned_zone': self.assigned_zone_code,
            'serial_connected': self.serial_conn is not None and self.serial_conn.is_open,
            'last_assignment_check': time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(self.last_assignment_check))
        }
    
    def close(self):
        """Cleanup resources"""
        if self.serial_conn and self.serial_conn.is_open:
            self.serial_conn.close()
            logging.info("🔌 Serial connection closed")