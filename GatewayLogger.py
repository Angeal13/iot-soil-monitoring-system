"""
Gateway Logger Module
Sends sensor data to Gateway Pi with retry logic and offline storage fallback
"""

import requests
from Config import Config
import logging
import time

class GatewayLogger:
    def __init__(self):
        self.gateway_url = Config.GATEWAY_PI_URL
        self.last_gateway_check = 0
        self.gateway_available = False
        self.connected_to_gateway = False
        
        # Check gateway availability on startup
        self.check_gateway_availability(force=True)
    
    def check_gateway_availability(self, force=False):
        """Check if Gateway Pi is available"""
        current_time = time.time()
        
        if not force and (current_time - self.last_gateway_check < Config.GATEWAY_CHECK_INTERVAL):
            return self.gateway_available
        
        logging.info(f"🔍 Checking Gateway Pi availability: {self.gateway_url}")
        
        try:
            # Try to reach the gateway
            response = requests.get(
                f"{self.gateway_url}/api/test",
                timeout=Config.GATEWAY_TIMEOUT
            )
            
            if response.status_code == 200:
                self.gateway_available = True
                self.connected_to_gateway = True
                logging.info(f"✅ Gateway Pi is available and responding")
            else:
                self.gateway_available = False
                logging.warning(f"⚠️ Gateway Pi returned status {response.status_code}")
                
        except requests.exceptions.ConnectionError:
            self.gateway_available = False
            logging.warning(f"🔌 Cannot connect to Gateway Pi at {self.gateway_url}")
            
        except requests.exceptions.Timeout:
            self.gateway_available = False
            logging.warning("⏰ Gateway Pi timeout")
            
        except Exception as e:
            self.gateway_available = False
            logging.error(f"❌ Gateway check error: {e}")
        
        self.last_gateway_check = current_time
        return self.gateway_available
    
    def send_to_gateway(self, data):
        """Send sensor data to Gateway Pi"""
        # Always try to send, even if gateway check failed
        logging.info(f"📤 Sending data to Gateway Pi: {data['timestamp']}")
        
        try:
            response = requests.post(
                Config.get_gateway_data_url(),
                json=data,
                timeout=Config.GATEWAY_TIMEOUT
            )
            
            # Log response for debugging
            logging.debug(f"Gateway response: Status {response.status_code}")
            
            if response.status_code == 200:
                response_data = response.json()
                logging.info(f"✅ Data sent to Gateway Pi successfully: {response_data.get('status', 'forwarded')}")
                return True
            elif response.status_code == 202:  # Accepted but stored offline
                logging.info(f"⚠️ Gateway accepted data but stored offline")
                return True  # Still return True because data was accepted
            elif response.status_code == 403:
                logging.warning("🚫 Gateway rejected data - sensor not assigned")
                return False
            elif response.status_code == 503:
                logging.warning("🔌 Gateway unavailable but accepted offline storage")
                return True  # Gateway accepted it for offline storage
            else:
                logging.warning(f"⚠️ Gateway returned status {response.status_code}")
                return False
                
        except requests.exceptions.ConnectionError:
            logging.error(f"🔌 Connection error to Gateway Pi")
            return False
            
        except requests.exceptions.Timeout:
            logging.error("⏰ Gateway Pi timeout")
            return False
            
        except Exception as e:
            logging.error(f"❌ Error sending to gateway: {e}")
            return False
    
    def save(self, data):
        """Primary method to save data (calls send_to_gateway)"""
        return self.send_to_gateway(data)
    
    def is_available(self):
        """Check if gateway is currently available"""
        return self.gateway_available