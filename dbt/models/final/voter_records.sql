{{ config(
    materialized='view',
    cluster_by=['household_id', 'resident_city', 'resident_zip', 'precinct_code']
    partition_by={"field": "registration_date", "data_type": "date"},
) }}

WITH cleaned_voter_data AS (
    SELECT
        TRIM(sos_voterid) AS sos_voterid,
        TRIM(UPPER(first_name)) AS first_name,
        TRIM(UPPER(middle_name)) AS middle_name,
        TRIM(UPPER(last_name)) AS last_name,
        TRIM(UPPER(suffix)) AS suffix,
        -- TODO (ai): Cast INT county num field to STRING (i.e. county code should begin with '0')
        county_number,
        county_id,
        SAFE_CAST(date_of_birth AS DATE) AS dob,
        SAFE_CAST(registration_date AS DATE) AS registration_date,
        TRIM(UPPER(voter_status)) AS voter_status,
        TRIM(UPPER(party_affiliation)) AS party_affiliation,
        TRIM(UPPER(residential_address1)) AS resident_address1,
        TRIM(UPPER(residential_secondary_addr)) AS resident_address2,
        TRIM(UPPER(residential_city)) AS resident_city,
        TRIM(UPPER(residential_state)) AS resident_state,
        -- TODO (ai): When casting INT zip to STRING add 0 depending on length (i.e. zip code should begin with '0')
        TRIM(CAST(residential_zip AS STRING)) AS resident_zip,
        residential_zip_plus4 AS resident_zip4,
        TRIM(UPPER(residential_country)) AS resident_country,
        residential_postal_code AS resident_postal_code,
        TRIM(UPPER(mailing_address1)) AS mailing_address1,
        TRIM(UPPER(mailing_secondary_address)) AS mailing_address2,
        TRIM(UPPER(mailing_city)) AS mailing_city,
        TRIM(UPPER(mailing_state)) AS mailing_state,
        -- TODO (ai): When casting INT zip to STRING add 0 depending on length (i.e. zip code should begin with '0')
        TRIM(CAST(mailing_zip AS STRING)) AS mailing_zip,
        mailing_zip_plus4 AS mailing_zip4,
        TRIM(UPPER(mailing_country)) AS mailing_country,
        mailing_postal_code,
        career_center,
        TRIM(UPPER(city)) AS city,
        city_school_district,
        county_court_district,
        congressional_district,
        court_of_appeals,
        edu_service_center_district,
        exempted_vill_school_district AS exempted_village_school_district,
        library AS library_district,
        local_school_district,
        municipal_court_district,
        TRIM(UPPER(precinct_name)) AS precinct_name,
        TRIM(UPPER(precinct_code)) AS precinct_code,
        state_board_of_education,
        state_representative_district,
        state_senate_district,
        township,
        village,
        ward,
        COALESCE(created_at, CURRENT_TIMESTAMP()) AS created_at
    FROM {{ source('ingest', 'staging_voter_records') }}
),

voter_households AS (
    SELECT 
        household_id,
        resident_address1,
        resident_city,
        resident_zip,
        county_number,
        precinct_name,
        voter_count
    FROM {{ ref('voter_households') }}
),

voter_history AS (
    SELECT 
        sos_voterid,
        TO_JSON_STRING(ARRAY_AGG(
            STRUCT(election_date, party_vote) 
            ORDER BY election_date DESC
        )) AS vote_history_json -- Example: [{"election_date": "2025-11-07", "party_vote": "D"} , ...]
    FROM {{ ref('voter_history') }}
    GROUP BY sos_voterid
),

voter_final AS(
    SELECT 
        c.*,
        h.household_id,
        v.vote_history
    FROM cleaned_voter_data c
    LEFT JOIN voter_households h
        ON c.resident_address1 = h.resident_address1
        AND c.resident_zip = h.resident_zip
    LEFT JOIN voter_history v
        ON c.sos_voter_id = v.sos_voter_id
),

voter_final_deduped AS (
    SELECT *, 
            ROW_NUMBER() OVER (PARTITION BY sos_voterid ORDER BY registration_date DESC) AS row_num
    FROM voter_final
)

SELECT * EXCEPT(row_num)
FROM voter_final_deduped 
WHERE row_num = 1
