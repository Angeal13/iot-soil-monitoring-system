"""
Main Controller Module
Orchestrates the entire IoT sensor system
"""

from SensorReader import SensorReader
from GatewayLogger import GatewayLogger
from OfflineLogger import OfflineLogger
from NetworkManager import NetworkManager
from Config import Config
import time
import logging
import signal
import sys
import json
from datetime import datetime

class MainController:
    def __init__(self):
        self.running = True
        self.cycles_completed = 0
        self.data_points_collected = 0
        self.last_sync_time = 0
        
        # Setup signal handlers for graceful shutdown
        signal.signal(signal.SIGINT, self.signal_handler)
        signal.signal(signal.SIGTERM, self.signal_handler)
        
        # Initialize components
        logging.info("🚀 Initializing IoT Sensor System Components")
        
        self.network = NetworkManager()
        self.sensor = SensorReader()
        self.gateway = GatewayLogger()
        self.offline = OfflineLogger()
        
        logging.info("✅ All components initialized successfully")
    
    def signal_handler(self, signum, frame):
        """Handle shutdown signals gracefully"""
        logging.info(f"⚠️ Received signal {signum}, shutting down gracefully...")
        self.running = False
    
    def sync_offline_data(self):
        """Sync offline data when network is available"""
        if not self.network.can_reach_gateway_pi():
            logging.info("📴 Gateway not available, skipping offline sync")
            return False
        
        current_time = time.time()
        
        # Don't sync too frequently (every 15 minutes max)
        if current_time - self.last_sync_time < 900:
            return True
        
        logging.info("🔄 Attempting to sync offline data")
        
        # Load a batch of offline records
        offline_batch = self.offline.load_batch(batch_size=20)
        
        if offline_batch.empty:
            logging.info("📭 No offline data to sync")
            return True
        
        successful_syncs = 0
        
        # Try to send each record
        for _, record in offline_batch.iterrows():
            try:
                # Convert record to dict
                data = record.to_dict()
                
                # Send to gateway
                if self.gateway.send_to_gateway(data):
                    successful_syncs += 1
                else:
                    # Stop on first failure to maintain order
                    break
                    
            except Exception as e:
                logging.error(f"❌ Error syncing record: {e}")
                break
        
        # Remove successfully synced records
        if successful_syncs > 0:
            self.offline.remove_synced(successful_syncs)
            logging.info(f"✅ Synced {successful_syncs} offline records")
            self.last_sync_time = current_time
            return True
        else:
            logging.warning("⚠️ Could not sync any offline records")
            return False
    
    def collect_and_process_data(self):
        """Collect sensor data and process it"""
        logging.info(f"🔄 Cycle {self.cycles_completed + 1} starting")
        
        # Check connectivity
        connectivity = self.network.check_all_connectivity()
        logging.info(f"📡 Connectivity: Internet={connectivity['internet']}, DB={connectivity['db_pi']}, Gateway={connectivity['gateway_pi']}")
        
        # Read sensor data
        sensor_data = self.sensor.read_sensor_data()
        
        if not sensor_data:
            logging.warning("📭 No sensor data collected")
            return
        
        self.data_points_collected += 1
        logging.info(f"📊 Data collected: {self.data_points_collected} total points")
        
        # Check if sensor is still assigned (data collection verifies this)
        if not self.sensor.is_assigned:
            logging.info("⏸️ Sensor not assigned - stopping collection")
            self.running = False
            return
        
        # Try to send data to gateway
        if connectivity['gateway_pi']:
            if self.gateway.save(sensor_data):
                # Successfully sent to gateway
                logging.info("✅ Data sent to Gateway Pi")
                
                # Try to sync offline data
                self.sync_offline_data()
            else:
                # Gateway save failed, store offline
                logging.warning("📴 Gateway save failed, storing offline")
                self.offline.save(sensor_data)
        else:
            # No gateway connection, store offline
            logging.info("💾 No gateway connection, storing offline")
            self.offline.save(sensor_data)
        
        # Update sensor info display periodically
        if self.cycles_completed % 12 == 0:  # Every hour (12 * 5min)
            sensor_info = self.sensor.get_sensor_info()
            logging.info(f"📟 Sensor Status: Assigned={sensor_info['is_assigned']}, Farm={sensor_info['assigned_farm']}, Zone={sensor_info['assigned_zone']}")
            
            # Show offline storage stats
            offline_stats = self.offline.get_stats()
            logging.info(f"💾 Offline Storage: {offline_stats['total_records']} records, {offline_stats['storage_size_kb']:.1f} KB")
    
    def run(self):
        """Main execution loop"""
        logging.info("=" * 50)
        logging.info("🏁 Starting main sensor monitoring loop")
        logging.info(f"⏰ Measurement interval: {Config.MEASUREMENT_INTERVAL} seconds")
        logging.info("=" * 50)
        
        try:
            while self.running:
                cycle_start_time = time.time()
                
                # Perform data collection and processing
                self.collect_and_process_data()
                
                self.cycles_completed += 1
                
                # Calculate sleep time to maintain consistent interval
                cycle_time = time.time() - cycle_start_time
                sleep_time = max(1, Config.MEASUREMENT_INTERVAL - cycle_time)
                
                # Log cycle completion
                logging.info(f"✅ Cycle {self.cycles_completed} completed in {cycle_time:.1f}s, sleeping for {sleep_time:.1f}s")
                logging.info("-" * 40)
                
                # Sleep until next cycle
                time.sleep(sleep_time)
                
        except KeyboardInterrupt:
            logging.info("👋 Stopped by user (KeyboardInterrupt)")
        except Exception as e:
            logging.error(f"💥 Unexpected error in main loop: {e}")
            import traceback
            logging.error(traceback.format_exc())
        finally:
            self.shutdown()
    
    def shutdown(self):
        """Clean shutdown procedure"""
        logging.info("🔴 Beginning system shutdown")
        
        # Close sensor connection
        if hasattr(self, 'sensor'):
            self.sensor.close()
        
        # Show final statistics
        logging.info("=" * 50)
        logging.info("📊 FINAL STATISTICS")
        logging.info(f"   Cycles completed: {self.cycles_completed}")
        logging.info(f"   Data points collected: {self.data_points_collected}")
        
        # Show offline storage status
        if hasattr(self, 'offline'):
            offline_stats = self.offline.get_stats()
            logging.info(f"   Offline records: {offline_stats['total_records']}")
        
        # Show sensor status
        if hasattr(self, 'sensor'):
            sensor_info = self.sensor.get_sensor_info()
            logging.info(f"   Sensor assigned: {sensor_info['is_assigned']}")
            if sensor_info['is_assigned']:
                logging.info(f"   Assigned to: Farm {sensor_info['assigned_farm']}, Zone {sensor_info['assigned_zone']}")
        
        logging.info("=" * 50)
        logging.info("🛑 IoT Sensor System stopped")
        
        # Flush logs
        logging.shutdown()

def main():
    """Entry point for the application"""
    try:
        # Validate configuration first
        if not Config.validate_config():
            print("❌ Configuration validation failed. Please check Config.py")
            sys.exit(1)
        
        # Create and run controller
        controller = MainController()
        controller.run()
        
    except Exception as e:
        print(f"💥 Fatal error: {e}")
        import traceback
        print(traceback.format_exc())
        sys.exit(1)

if __name__ == "__main__":
    main()