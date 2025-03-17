{{ config(
    materialized='view',
    cluster_by=['voted_party', 'sos_voterid'],
    partition_by={"field": "election_date", "data_type": "date"}
) }}

WITH voter_history AS (
    SELECT sos_voterid,
        PRIMARY_03_07_2000, -- TODO (ai): Figure out a dynamic way to grab all of these columns
    FROM {{ source('ingest', 'staging_voter_records') }}
),

unpivoted_vote_history AS (
    SELECT
        sos_voterid,
        vote_column,
        voted_party
    FROM voter_history
    UNPIVOT (
        party_vote FOR vote_column IN (
            PRIMARY_03_07_2000, -- TODO (ai): Figure out a dynamic way to grab all of these columns
        )
    )
),

final_vote_history AS (
    SELECT
        sos_voterid,
        -- Extract election type (PRIMARY, GENERAL, SPECIAL)
        REGEXP_EXTRACT(vote_column, r'^(PRIMARY|GENERAL|SPECIAL)') AS election_type,
        -- Convert MM_DD_YYYY to YYYY-MM-DD format
        SAFE.PARSE_DATE('%m_%d_%Y', REGEXP_EXTRACT(vote_column, r'(\d{2}_\d{2}_\d{4})')) AS election_date,
        voted_party
    FROM unpivoted_vote_history
)

SELECT * FROM final_vote_history;
