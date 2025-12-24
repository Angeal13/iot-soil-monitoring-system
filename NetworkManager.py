"""
Network Manager Module
Handles internet connectivity checks and network operations
"""

import requests
from urllib.request import urlopen, Request
from urllib.error import URLError
import time
import logging
from Config import Config

class NetworkManager:
    def __init__(self):
        self.last_internet_check = 0
        self.internet_available = False
        self.db_pi_available = False
        self.gateway_pi_available = False
        
        # Initial connectivity check
        self.check_all_connectivity(force=True)
    
    def check_internet(self):
        """Check general internet connectivity"""
        logging.debug("🌐 Checking internet connectivity")
        
        for url in Config.INTERNET_TEST_URLS:
            try:
                # Quick test with short timeout
                response = requests.get(url, timeout=3, allow_redirects=False)
                if response.status_code in [200, 301, 302]:
                    self.internet_available = True
                    logging.info(f"✅ Internet connection available via {url}")
                    return True
            except:
                continue  # Try next URL
        
        self.internet_available = False
        logging.warning("🌐 No internet connection")
        return False
    
    def check_db_pi(self):
        """Check if Database Pi (appV7.py) is reachable"""
        try:
            response = requests.get(
                Config.get_health_url(),
                timeout=5
            )
            
            if response.status_code == 200:
                self.db_pi_available = True
                logging.info("✅ Database Pi is reachable")
                return True
            else:
                self.db_pi_available = False
                logging.warning(f"⚠️ Database Pi returned status {response.status_code}")
                return False
                
        except requests.exceptions.RequestException:
            self.db_pi_available = False
            logging.warning("🔌 Cannot connect to Database Pi")
            return False
    
    def check_gateway_pi(self):
        """Check if Gateway Pi is reachable"""
        try:
            response = requests.get(
                f"{Config.GATEWAY_PI_URL}/api/test",
                timeout=5
            )
            
            if response.status_code == 200:
                self.gateway_pi_available = True
                logging.info("✅ Gateway Pi is reachable")
                return True
            else:
                self.gateway_pi_available = False
                logging.warning(f"⚠️ Gateway Pi returned status {response.status_code}")
                return False
                
        except requests.exceptions.RequestException:
            self.gateway_pi_available = False
            logging.warning("🔌 Cannot connect to Gateway Pi")
            return False
    
    def check_all_connectivity(self, force=False):
        """Check all network connections"""
        current_time = time.time()
        
        # Don't check too frequently (every 5 minutes max)
        if not force and (current_time - self.last_internet_check < 300):
            return {
                'internet': self.internet_available,
                'db_pi': self.db_pi_available,
                'gateway_pi': self.gateway_pi_available
            }
        
        logging.info("🔗 Running comprehensive connectivity check")
        
        self.check_internet()
        self.check_db_pi()
        self.check_gateway_pi()
        
        self.last_internet_check = current_time
        
        return {
            'internet': self.internet_available,
            'db_pi': self.db_pi_available,
            'gateway_pi': self.gateway_pi_available
        }
    
    def has_internet(self):
        """Check if internet is available (cached result)"""
        current_time = time.time()
        
        # Refresh cache every 5 minutes
        if current_time - self.last_internet_check > 300:
            self.check_all_connectivity()
        
        return self.internet_available
    
    def can_reach_db_pi(self):
        """Check if Database Pi is reachable"""
        return self.db_pi_available
    
    def can_reach_gateway_pi(self):
        """Check if Gateway Pi is reachable"""
        return self.gateway_pi_available
    
    def get_connectivity_status(self):
        """Get comprehensive connectivity status"""
        return {
            'timestamp': time.strftime('%Y-%m-%d %H:%M:%S'),
            'internet': self.internet_available,
            'db_pi': self.db_pi_available,
            'gateway_pi': self.gateway_pi_available,
            'last_check': time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(self.last_internet_check))
        }