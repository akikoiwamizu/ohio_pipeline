# ohio-pipeline

Used to ingest, transform, and load the Ohio state voter file into GCP.

## Virtual Environment

```
conda create --name oh-voters python=3.10
conda activate oh-voters
pip install -r cloud-functions/requirements.txt
```

## Repo Directory

```
ohio-voter-file/                        # Root of GitHub repo
│── cloud-functions/                    # Cloud Function source code
│   ├── gcs_to_bigquery.py              # Main ETL script
│   ├── requirements.txt                # Python dependencies
│── dbt/                                # dbt project
│   ├── models/                         # dbt models (SQL transformations)
│   │   ├── staging/                    # Staging models
│   │   │   ├── schema.yml              # Staging table model
│   │   ├── final/                      # Production models
│   │   │   ├── schema.yml              # Production table schemas
│   │   │   ├── voter_history.yml       # Production table model: voter history since 2000
│   │   │   ├── voter_households.yml    # Production table model: voter households aggregated by hashed address
│   │   │   ├── voter_records.yml       # Production table model: voter records deduplicated & normalized
│   ├── dbt_project.yml                 # dbt configuration file
│   ├── packages.yml                    # dbt dependencies
│   ├── profiles.yml                    # BigQuery connection config
│── .gitignore                          # Ignore sensitive files
│── README.md                           # Documentation
```
