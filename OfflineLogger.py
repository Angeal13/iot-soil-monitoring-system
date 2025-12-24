"""
Offline Logger Module
Stores sensor data locally when internet/gateway is unavailable
"""

import pandas as pd
from Config import Config
import os
import logging
import json
from datetime import datetime

class OfflineLogger:
    def __init__(self):
        self.storage_path = Config.OFFLINE_STORAGE
        self.max_records = Config.MAX_OFFLINE_RECORDS
        
        # Ensure directory exists
        os.makedirs(os.path.dirname(self.storage_path), exist_ok=True)
        
        logging.info(f"💾 Offline storage initialized: {self.storage_path}")
        logging.info(f"📊 Max offline records: {self.max_records}")
    
    def save(self, data):
        """Append sensor data to offline CSV storage"""
        try:
            # Create DataFrame from single data point
            df_new = pd.DataFrame([data])
            
            # Check if file exists
            if os.path.exists(self.storage_path):
                # Read existing data
                df_existing = pd.read_csv(self.storage_path)
                
                # Append new data and keep only last max_records
                df_combined = pd.concat([df_existing, df_new], ignore_index=True)
                
                # Trim to max records
                if len(df_combined) > self.max_records:
                    df_combined = df_combined.tail(self.max_records)
                    logging.info(f"✂️ Trimmed offline storage to {self.max_records} records")
            else:
                df_combined = df_new
            
            # Save to CSV
            df_combined.to_csv(self.storage_path, index=False)
            
            current_count = len(df_combined)
            logging.info(f"💾 Stored offline (Total: {current_count})")
            return True
            
        except Exception as e:
            logging.error(f"❌ Offline save failed: {e}")
            return False
    
    def load_all(self):
        """Load all offline records"""
        try:
            if os.path.exists(self.storage_path):
                df = pd.read_csv(self.storage_path)
                logging.info(f"📖 Loaded {len(df)} offline records")
                return df
            else:
                logging.info("📭 No offline records found")
                return pd.DataFrame()
                
        except Exception as e:
            logging.error(f"❌ Failed to load offline data: {e}")
            return pd.DataFrame()
    
    def load_batch(self, batch_size=50):
        """Load a batch of offline records for syncing"""
        try:
            if os.path.exists(self.storage_path):
                df = pd.read_csv(self.storage_path)
                if len(df) > 0:
                    # Return oldest records first (FIFO)
                    batch = df.head(batch_size)
                    logging.info(f"📦 Loaded batch of {len(batch)} records for syncing")
                    return batch
            return pd.DataFrame()
            
        except Exception as e:
            logging.error(f"❌ Failed to load batch: {e}")
            return pd.DataFrame()
    
    def remove_synced(self, count):
        """Remove successfully synced records from offline storage"""
        try:
            if not os.path.exists(self.storage_path):
                return True
            
            df = pd.read_csv(self.storage_path)
            
            if count >= len(df):
                # All records synced, delete file
                os.remove(self.storage_path)
                logging.info(f"✅ All {count} records synced, offline storage cleared")
            else:
                # Remove synced records
                df = df.iloc[count:]
                df.to_csv(self.storage_path, index=False)
                logging.info(f"✅ Removed {count} synced records, {len(df)} remaining")
            
            return True
            
        except Exception as e:
            logging.error(f"❌ Failed to remove synced records: {e}")
            return False
    
    def clear(self):
        """Clear all offline data"""
        try:
            if os.path.exists(self.storage_path):
                os.remove(self.storage_path)
                logging.info("🧹 Offline storage cleared")
                return True
            return True
            
        except Exception as e:
            logging.error(f"❌ Failed to clear offline data: {e}")
            return False
    
    def get_stats(self):
        """Get offline storage statistics"""
        try:
            if os.path.exists(self.storage_path):
                df = pd.read_csv(self.storage_path)
                return {
                    'total_records': len(df),
                    'storage_size_kb': os.path.getsize(self.storage_path) / 1024,
                    'oldest_record': df['timestamp'].min() if len(df) > 0 else None,
                    'newest_record': df['timestamp'].max() if len(df) > 0 else None
                }
            else:
                return {'total_records': 0, 'storage_size_kb': 0}
                
        except Exception as e:
            logging.error(f"❌ Failed to get offline stats: {e}")
            return {'total_records': 0, 'storage_size_kb': 0, 'error': str(e)}