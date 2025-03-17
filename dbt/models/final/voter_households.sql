{{ config(
    materialized='view',
    cluster_by=['resident_zip', 'resident_city', 'precinct_code']
) }}

WITH unique_households AS (
    SELECT
        MD5(ARRAY_TO_STRING([TRIM(UPPER(residential_address1)), TRIM(UPPER(residential_city)), TRIM(CAST(residential_zip AS STRING))], '|')) AS household_id,
        TRIM(UPPER(residential_address1)) AS resident_address1,
        TRIM(UPPER(residential_city)) AS resident_city,
        TRIM(CAST(residential_zip AS STRING)) AS resident_zip,
        county_number,
        TRIM(UPPER(precinct_code)) AS precinct_code,
        COUNT(*) AS voter_count  -- Number of voters per household
    FROM {{ source('ingest', 'staging_voter_records') }}
    WHERE residential_address1 IS NOT NULL  -- Ignore missing addresses
    GROUP BY residential_zip, residential_city, precinct_code
)

SELECT * FROM unique_households
