import os
import sys
import re
from pymongo import MongoClient
from pymongo.errors import ConnectionFailure, ServerSelectionTimeoutError
try:
    import boto3
    from botocore.exceptions import NoCredentialsError, PartialCredentialsError, ClientError
except ImportError:
    print("WARNING: 'boto3' library not found. S3 uploads will be disabled.")
    print("To enable S3 uploads, run: pip install boto3")
    boto3 = None
    ClientError = None
    NoCredentialsError = None
    PartialCredentialsError = None

MONGO_URI = "mongodb://readonly:TUpJW2p7HZT5QikMSn@34.248.98.129:27017/"
DB_NAME = "airserver_logs"
INDEX_COLLECTION = "box_to_collection"


UPLOAD_TO_S3 = True
S3_BUCKET_NAME = "airserver-logs-processed"  

def create_log_files(db, s3_client, bucket_name):
    """
    Fetches log data from dynamic collection names and writes to local files.
    """
    try:
        index_col = db[INDEX_COLLECTION]
        collection_docs = list(index_col.find())
        
        if not collection_docs:
            print(f"No collections found in '{INDEX_COLLECTION}'. Exiting.")
            return

        print(f"Found {len(collection_docs)} log collections to process.")

        for doc in collection_docs:
            collection_name = doc.get("collection")
            if not collection_name:
                print(f"Skipping document, missing 'collection' field: {doc}")
                continue

            print(f"\nProcessing collection: '{collection_name}'...")
            log_collection = db[collection_name]

            try:
                distinct_filenames = log_collection.distinct("logFileName")
            except Exception as e:
                print(f"  [ERROR] Could not query distinct filenames in '{collection_name}': {e}")
                continue
                
            print(f"  Found {len(distinct_filenames)} distinct log files.")

            for filename in distinct_filenames:
                if not filename:
                    print("  Skipping entry with empty filename.")
                    continue
                
                new_filename = filename.replace(".gz", ".txt")
                    
                print(f"    -> Writing file: {new_filename} (from {filename})")
                
                year = "YYYY_UNKNOWN"
                box_ip_s3 = "UNKNOWN_BOX_IP" 
                try:
                    one_log_doc = log_collection.find_one({"logFileName": filename})
                    if one_log_doc:
                        if 'time' in one_log_doc and one_log_doc['time']:
                            year = str(one_log_doc['time'].year)
                        else:
                            print(f"       ... Warning: Could not find valid 'time' field. Falling back to filename regex for year.")
                            match = re.search(r'(\d{4})\d{4}_\d{6}', filename)
                            if match:
                                year = match.group(1)
                            else:
                                 print(f"       ... Warning: Could not parse year from filename '{filename}'. Using fallback '{year}'.")
                        
                        if 'boxIP' in one_log_doc and one_log_doc['boxIP']:
                            box_ip_s3 = one_log_doc['boxIP'].replace('-','.')
                        else:
                            print(f"       ... Warning: Could not find 'boxIP' field in doc. Using fallback '{box_ip_s3}'.")

                    else:
                        print(f"       ... Warning: Could not find any doc for {filename}. Falling back to filename regex for year.")
                        match = re.search(r'(\d{4})\d{4}_\d{6}', filename)
                        if match:
                            year = match.group(1)
                        else:
                             print(f"       ... Warning: Could not parse year from filename '{filename}'. Using fallback '{year}'.")

                except Exception as e:
                    print(f"       ... Warning: Error getting year/boxIP from 'time' field: {e}. Falling back to regex.")
                    try:
                        match = re.search(r'(\d{4})\d{4}_\d{6}', filename)
                        if match:
                            year = match.group(1)
                        else:
                            print(f"       ... Warning: Could not parse year from filename '{filename}'. Using fallback '{year}'.")
                    except Exception as re_e:
                        print(f"       ... Warning: Regex error parsing year. Using '{year}'. {re_e}")

                try:
                    directory = os.path.dirname(new_filename)
                    if directory:
                        os.makedirs(directory, exist_ok=True)

                    log_cursor = log_collection.find(
                        {"logFileName": filename}
                    ).sort("time", 1)

                    line_count = 0

                    with open(new_filename, 'w', encoding='utf-8') as f:
                        for log_doc in log_cursor:
                            time_str = log_doc.get('time', {}).isoformat()
                            box_ip = log_doc.get('boxIP', 'N/A')
                            service = log_doc.get('serviceName', 'N/A')
                            log_line = log_doc.get('logLine', '')
                            
                            output_line = f"{time_str} {box_ip} {service} {log_line}\n"
                            f.write(output_line)
                            line_count += 1
                    
                    print(f"       ... Wrote {line_count} lines.")


                    if UPLOAD_TO_S3 and s3_client:

                        base_filename = os.path.basename(new_filename)
                        
                        s3_object_key = f"logs/{year}/{box_ip_s3}/{base_filename}"
                        
                        try:
                            s3_client.head_object(Bucket=bucket_name, Key=s3_object_key)
                            print(f"       ... File already exists in S3 at {s3_object_key}. Skipping upload.")
                        
                        except ClientError as e:
                            if e.response['Error']['Code'] == '404':
                                print(f"       -> Uploading to S3 path: {s3_object_key}...")
                                try:
                                    s3_client.upload_file(new_filename, bucket_name, s3_object_key)
                                    print(f"       ... Successfully uploaded to S3.")
                                except ClientError as upload_e:
                                    print(f"    [ERROR] S3 ClientError: Failed to upload {new_filename}. Check bucket permissions/name.")
                                    print(f"    Details: {upload_e}")
                                except Exception as upload_e:
                                    print(f"    [ERROR] An unexpected error occurred during S3 upload: {upload_e}")
                            else:
                                print(f"    [ERROR] S3 ClientError checking for file existence: {e}")

                        except Exception as e:
                            print(f"    [ERROR] An unexpected error occurred checking S3: {e}")

                except IOError as e:
                    print(f"    [ERROR] Could not write to file {new_filename}: {e}")
                except Exception as e:
                    print(f"    [ERROR] An unexpected error occurred for {new_filename}: {e}")

    except Exception as e:
        print(f"An error occurred while processing collections: {e}")


def main():
    """
    Main function to connect to MongoDB and start the log processing.
    """
    try:
        print(f"Connecting to MongoDB at {MONGO_URI}...")
        client = MongoClient(MONGO_URI, serverSelectionTimeoutMS=5000)
        client.server_info() 
        print("Connection successful.")
        
        db = client[DB_NAME]
        
        s3_client = None
        global UPLOAD_TO_S3 
        
        if UPLOAD_TO_S3:
            if boto3 is None:
                print("\nS3 uploads disabled because 'boto3' library is missing.")
                UPLOAD_TO_S3 = False
            else:
                print(f"\nS3 uploads enabled. Connecting to S3...")
                try:
                    s3_client = boto3.client('s3')
                    s3_client.head_bucket(Bucket=S3_BUCKET_NAME) 
                    print(f"Successfully connected to S3 and verified bucket '{S3_BUCKET_NAME}'.")
                except (NoCredentialsError, PartialCredentialsError):
                    print("  [ERROR] AWS credentials not found. Please configure boto3.")
                    print("  S3 uploads will be SKIPPED.")
                    UPLOAD_TO_S3 = False
                except ClientError as e:
                    if e.response['Error']['Code'] == '404':
                        print(f"  [ERROR] S3 bucket '{S3_BUCKET_NAME}' not found.")
                    elif e.response['Error']['Code'] == '403':
                        print(f"  [ERROR] Access denied to S3 bucket '{S3_BUCKET_NAME}'.")
                    else:
                        print(f"  [ERROR] S3 ClientError: {e}")
                    print("  S3 uploads will be SKIPPED.")
                    UPLOAD_TO_S3 = False
                except Exception as e:
                    print(f"  [ERROR] An unexpected error occurred connecting to S3: {e}")
                    print("  S3 uploads will be SKIPPED.")
                    UPLOAD_TO_S3 = False
        
        create_log_files(db, s3_client, S3_BUCKET_NAME)
        
    except (ConnectionFailure, ServerSelectionTimeoutError) as e:
        print(f"Error: Could not connect to MongoDB at {MONGO_URI}.")
        print("Please ensure MongoDB is running and the MONGO_URI is correct.")
        print(f"Details: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"An unexpected error occurred: {e}")
        sys.exit(1)
    finally:
        if 'client' in locals():
            client.close()
            print("\nMongoDB connection closed.")

if __name__ == "__main__":
    print("--- MongoDB Log Exporter ---")
    print("This script will create local log files based on 'logFileName' entries.")
    try:
        import pymongo
    except ImportError:
        print("\n[FATAL ERROR] The 'pymongo' library is not installed.")
        print("Please install it by running: pip install pymongo")
        sys.exit(1)
        
    main()

