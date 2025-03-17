import os
import logging
import functions_framework
from google.cloud import bigquery, secretmanager, storage

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def get_secret(secret_name: str) -> str:
    """Retrieves a secret from Google Secret Manager"""
    client = secretmanager.SecretManagerServiceClient()
    project_id = os.getenv("GCP_PROJECT_ID")

    if not project_id:
        raise ValueError("GCP_PROJECT_ID environment variable is missing.")

    secret_path = f"projects/{project_id}/secrets/{secret_name}/versions/latest"
    response = client.access_secret_version(name=secret_path)

    return response.payload.data.decode("UTF-8")


def check_table_exists(client: bigquery.Client, dataset_id: str, table_id: str) -> None:
    """Creates an empty table without a schema if it does not exist in BigQUery"""
    dataset_ref = client.dataset(dataset_id)
    table_ref = dataset_ref.table(table_id)

    try:
        client.get_table(table_ref)  # If table exists, do nothing
    except Exception:
        logger.info(f"Table {table_id} does not exist. Creating it without a schema...")
        table = bigquery.Table(table_ref)
        client.create_table(table)  # If table doesn't exist, create an empty table
        logger.info(f"Created empty table in BigQuery: {table_id}")


# Triggered by a new batch folder upload in GCS
@functions_framework.cloud_event
def gcs_to_bigquery(cloud_event: functions_framework.CloudEvent) -> None:
    """Triggered when a .gz file is uploaded to Cloud Storage then loads all .gz files into BigQuery"""

    # Extract Eventarc message safely
    try:
        event_data = cloud_event.data
        bucket_name = event_data["bucket"]
        file_name = event_data["name"]  # Example: "batch_20250317/file1.txt.gz"
    except Exception as e:
        logger.error(f"Failed to decode Eventarc message: {e}")
        return

    logger.info(f"Received Eventarc trigger: gs://{bucket_name}/{file_name}")

    # Get secrets from Secret Manager
    GCP_PROJECT_ID = get_secret("GCP_PROJECT_ID")
    BIGQUERY_DATASET = get_secret("BIGQUERY_DATASET")
    STAGING_TABLE = get_secret("BIGQUERY_STAGING_TABLE")
    TEMP_TABLE = get_secret("BIGQUERY_TEMP_TABLE")

    # Initiate BQ client
    client = bigquery.Client()

    # Step 1: Ensure BigQuery tables exist before loading data
    for table in [TEMP_TABLE, STAGING_TABLE]:
        check_table_exists(client, BIGQUERY_DATASET, table)

    # Extract the batch folder name (i.e. gets "batch_20250317" from the path)
    batch_folder = "/".join(file_name.split("/")[:-1])
    if not batch_folder:
        logger.error(f"Invalid batch folder name extracted from {file_name}")
        return

    # Initiate GCS client & get bucket details
    storage_client = storage.Client()
    bucket = storage_client.bucket(bucket_name)

    # Step 2: List all new .gz files in Cloud Storage
    blobs = list(bucket.list_blobs(prefix=batch_folder))
    gz_files = [f"gs://{bucket_name}/{blob.name}" for blob in blobs if blob.name.endswith(".gz")]

    # TODO (ai): check if all .gz files expected (total of 4) are present

    if not gz_files:
        logger.warning(f"Skipping non-gz file(s) found in Cloud Storage folder: {batch_folder}")
        return

    logger.info(f"Loading files from {batch_folder} to {TEMP_TABLE}: {gz_files}")

    # Step 3: Load all .gz files into a temporary BigQuery table
    job_config = bigquery.LoadJobConfig(
        source_format=bigquery.SourceFormat.CSV,
        autodetect=True,  # Let BigQuery infer the schema
        skip_leading_rows=1,
        write_disposition="WRITE_TRUNCATE",
        column_name_character_map="V2",  # Handle column name issues (i.e. "PRIMARY-03/07/2000" -> "PRIMARY_03_07_2000")
    )

    load_job = client.load_table_from_uri(
        gz_files, f"{GCP_PROJECT_ID}.{BIGQUERY_DATASET}.{TEMP_TABLE}", job_config=job_config
    )
    load_job.result()
    logger.info(f"Loaded {load_job.output_rows} rows into {TEMP_TABLE}")

    # Step 4: Atomically replace staging table with temp table's new data
    query = f"""
    CREATE OR REPLACE TABLE `{GCP_PROJECT_ID}.{BIGQUERY_DATASET}.{STAGING_TABLE}`
    AS SELECT * FROM `{GCP_PROJECT_ID}.{BIGQUERY_DATASET}.{TEMP_TABLE}`;
    """
    client.query(query).result()
    logger.info(f"Staging table {STAGING_TABLE} successfully replaced with {TEMP_TABLE}")
