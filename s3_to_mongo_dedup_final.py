import boto3
from pymongo import MongoClient, errors

# ---------- CONFIG ----------
BUCKET_NAME = "airserver-logs-processed"
PREFIX = "log/2025/"
MONGO_URI = "mongodb+srv://afl-reports:FOLtyVildalcRpeq@afl.tal51.mongodb.net/"
DB_NAME = "airserver_logs"
COLLECTION_NAME = "s3_files"

# ---------- AWS + Mongo Setup ----------
s3 = boto3.client("s3")
mongo_client = MongoClient(MONGO_URI)
collection = mongo_client[DB_NAME][COLLECTION_NAME]

# Ensure a unique index exists on s3fileKey
collection.create_index("s3fileKey", unique=True)

# ---------- Recursive Key Listing ----------
def list_all_keys(bucket, prefix):
    """Yield all object keys from an S3 bucket under the given prefix."""
    paginator = s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        for obj in page.get("Contents", []):
            yield obj["Key"]

# ---------- Insert Batch with Deduplication ----------
def insert_batch(batch):
    """Insert a batch of documents while skipping duplicates."""
    inserted = 0
    skipped = 0
    for doc in batch:
        try:
            collection.insert_one(doc)
            inserted += 1
        except errors.DuplicateKeyError:
            skipped += 1
        except Exception as e:
            print(f" Unexpected error: {e}")
    return inserted, skipped

# ---------- Main ----------
def main():
    print(f"Fetching S3 keys from s3://{BUCKET_NAME}/{PREFIX} ...")
    total_inserted = 0
    total_skipped = 0
    batch = []

    for key in list_all_keys(BUCKET_NAME, PREFIX):
        if key.endswith('/'):
            continue

        batch.append({
            "s3fileKey": key,
            "n8n": "unprocessed"
        })

        if len(batch) >= 500:
            inserted, skipped = insert_batch(batch)
            total_inserted += inserted
            total_skipped += skipped
            print(f"Inserted {total_inserted} | Skipped {total_skipped}")
            batch = []

    if batch:
        inserted, skipped = insert_batch(batch)
        total_inserted += inserted
        total_skipped += skipped

    print(f"\n✅ Done!\nInserted: {total_inserted}\nSkipped (already existed): {total_skipped}")

# ---------- Entry Point ----------
if __name__ == "__main__":
    main()
