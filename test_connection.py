#!/usr/bin/env python3
"""
Test script to verify sensor connectivity with correct IP
"""
import requests
import time
from Config import Config

def test_connections():
    print("=" * 60)
    print("🔍 TESTING NETWORK CONNECTIONS")
    print("=" * 60)
    
    print(f"\n📊 CURRENT CONFIGURATION:")
    print(f"   Machine ID: {Config.get_machine_id()}")
    print(f"   DB Pi URL: {Config.DB_PI_URL}")
    print(f"   Gateway URL: {Config.GATEWAY_PI_URL}")
    
    # Test Database Pi (appV7.py at 192.168.1.95)
    print(f"\n1. TESTING DATABASE PI ({Config.DB_PI_URL})...")
    try:
        response = requests.get(f"{Config.DB_PI_URL}/api/test", timeout=5)
        print(f"   ✅ Success! Status: {response.status_code}")
        print(f"   Response: {response.json()}")
    except Exception as e:
        print(f"   ❌ Failed: {e}")
    
    # Test Gateway Pi
    print(f"\n2. TESTING GATEWAY PI ({Config.GATEWAY_PI_URL})...")
    try:
        response = requests.get(f"{Config.GATEWAY_PI_URL}/api/test", timeout=5)
        print(f"   ✅ Success! Status: {response.status_code}")
        print(f"   Response: {response.json()}")
    except Exception as e:
        print(f"   ❌ Failed: {e}")
    
    # Test sensor assignment
    print(f"\n3. TESTING SENSOR ASSIGNMENT CHECK...")
    machine_id = Config.get_machine_id()
    try:
        response = requests.get(
            f"{Config.GATEWAY_PI_URL}/api/sensors/{machine_id}/assignment",
            timeout=5
        )
        print(f"   ✅ Success! Status: {response.status_code}")
        print(f"   Response: {response.json()}")
    except Exception as e:
        print(f"   ❌ Failed: {e}")
        
        # Try direct to DB Pi
        try:
            response = requests.get(
                f"{Config.DB_PI_URL}/api/sensors/{machine_id}/assignment",
                timeout=5
            )
            print(f"   ⚠️ Direct DB Pi check: Status {response.status_code}")
            print(f"   Response: {response.json()}")
        except Exception as e2:
            print(f"   ❌ Direct DB Pi also failed: {e2}")
    
    # Test sensor data sending
    print(f"\n4. TESTING SENSOR DATA SENDING...")
    test_data = {
        'machine_id': machine_id,
        'timestamp': time.strftime("%Y-%m-%d %H:%M:%S"),
        'moisture': 50.5,
        'temperature': 25.3,
        'conductivity': 120.0,
        'ph': 6.8,
        'nitrogen': 15.0,
        'phosphorus': 10.0,
        'potassium': 20.0
    }
    
    try:
        response = requests.post(
            f"{Config.GATEWAY_PI_URL}/api/sensor-data",
            json=test_data,
            timeout=10
        )
        print(f"   ✅ Success! Status: {response.status_code}")
        print(f"   Response: {response.json()}")
    except Exception as e:
        print(f"   ❌ Failed: {e}")
    
    print(f"\n" + "=" * 60)
    print("🏁 TEST COMPLETE")
    print("=" * 60)

if __name__ == "__main__":
    test_connections()