"""
Configuration for IoT Soil Monitoring System
Database Pi: appV7.py server for assignment checks
Gateway Pi: For data forwarding
"""

import serial
import time
import pandas as pd
from datetime import datetime
import uuid
import sys

class Config:
    # ========================
    # NETWORK CONFIGURATION
    # ========================
    
    # Database Raspberry Pi (appV7.py server) - UPDATED TO CORRECT IP
    DB_PI_URL = "http://192.168.1.95:5000"  # ← appV7.py runs here
    
    # Gateway Raspberry Pi (for data forwarding) - UPDATE THIS to your Gateway Pi IP
    GATEWAY_PI_URL = "http://192.168.1.80:5000"  # ← Your Gateway Pi IP
    
    # API Timeouts
    DB_TIMEOUT = 10
    GATEWAY_TIMEOUT = 10
    
    # ========================
    # SENSOR HARDWARE CONFIG
    # ========================
    
    SERIAL_PORT = '/dev/ttyUSB0'  # On Linux/Raspberry Pi
    SERIAL_BAUDRATE = 9600
    SERIAL_TIMEOUT = 1
    RESPONSE_LENGTH = 19  # For your soil sensor
    
    # Modbus command with CRC
    MODBUS_COMMAND = bytes([0x01, 0x03, 0x00, 0x00, 0x00, 0x07, 0x04, 0x08])
    
    # ========================
    # SYSTEM BEHAVIOR CONFIG
    # ========================
    
    MEASUREMENT_INTERVAL = 300  # 5 minutes between measurements
    ASSIGNMENT_CHECK_INTERVAL = 14400  # Check assignment every 4 hours
    GATEWAY_CHECK_INTERVAL = 3600  # Check gateway every hour
    MAX_RETRY_ATTEMPTS = 3
    RETRY_DELAY = 5
    
    # ========================
    # OFFLINE STORAGE CONFIG
    # ========================
    
    OFFLINE_STORAGE = '/home/pi/sensor_data/offline_data.csv'
    MAX_OFFLINE_RECORDS = 1000
    
    # ========================
    # LOGGING CONFIG
    # ========================
    
    LOG_FILE = '/home/pi/sensor_data/sensor_system.log'
    LOG_LEVEL = 'INFO'  # DEBUG, INFO, WARNING, ERROR
    
    # ========================
    # INTERNET CONNECTIVITY TEST
    # ========================
    
    INTERNET_TEST_URLS = [
        DB_PI_URL + '/api/test',  # Test DB Pi connection
        GATEWAY_PI_URL + '/api/test',  # Test Gateway Pi connection
        'http://www.google.com'  # Test general internet
    ]
    
    # ========================
    # API ENDPOINTS
    # ========================
    
    @classmethod
    def get_assignment_url(cls, machine_id):
        """Get URL for checking sensor assignment status"""
        return f"{cls.DB_PI_URL}/api/sensors/{machine_id}/assignment"
    
    @classmethod
    def get_registration_url(cls):
        """Get URL for sensor registration"""
        return f"{cls.DB_PI_URL}/api/sensors/register"
    
    @classmethod
    def get_gateway_data_url(cls):
        """Get URL for sending data to Gateway Pi"""
        return f"{cls.GATEWAY_PI_URL}/api/sensor-data"
    
    @classmethod
    def get_health_url(cls):
        """Get health check URL"""
        return f"{cls.DB_PI_URL}/api/test"
    
    # ========================
    # SYSTEM IDENTIFICATION
    # ========================
    
    @classmethod
    def get_machine_id(cls):
        """Get unique machine ID for this sensor device"""
        return str(uuid.getnode())
    
    # ========================
    # VALIDATION METHODS
    # ========================
    
    @classmethod
    def validate_config(cls):
        """Validate all configuration settings"""
        errors = []
        
        if not cls.SERIAL_PORT:
            errors.append("SERIAL_PORT is not set")
        
        if cls.MEASUREMENT_INTERVAL < 30:
            errors.append("MEASUREMENT_INTERVAL should be at least 30 seconds")
        
        if cls.RESPONSE_LENGTH <= 0:
            errors.append("RESPONSE_LENGTH must be positive")
        
        if not cls.DB_PI_URL.startswith('http'):
            errors.append("DB_PI_URL must start with http:// or https://")
        
        if not cls.GATEWAY_PI_URL.startswith('http'):
            errors.append("GATEWAY_PI_URL must start with http:// or https://")
        
        if errors:
            print("Configuration errors:")
            for error in errors:
                print(f"  - {error}")
            return False
        
        print("✅ Configuration validated successfully")
        return True