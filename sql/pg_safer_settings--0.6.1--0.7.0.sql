-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION pg_safer_settings" to load this file. \quit


/**
 * CHANGELOG.md:
 *
 * - The license of `pg_safer_settings` was changed from AGPL 3.0 to the
 *   PostgreSQL license.
 */
create or replace function pg_safer_settings_meta_pgxn()
    returns jsonb
    stable
    language sql
    return jsonb_build_object(
        'name'
        ,'pg_safer_settings'
        ,'abstract'
        ,'A handful of functions and mechanisms to make dealing with settings in Postgres a bit … safer.'
        ,'description'
        ,'The pg_safer_settings extension bundles a handful of functions and mechanisms to make dealing with'
            ' settings in Postgres a bit … safer.'
        ,'version'
        ,pg_safer_settings_version()
        ,'maintainer'
        ,array[
            'Rowan Rodrik van der Molen <rowan@bigsmoke.us>'
        ]
        ,'license'
        ,'postgresql'
        ,'prereqs'
        ,'{
            "runtime": {
                "requires": {
                    "pg_utility_trigger_functions": 0
                }
            },
            "test": {
                "requires": {
                    "pgtap": 0
                }
            },
            "develop": {
                "recommends": {
                    "pg_readme": 0
                }
            }
        }'::jsonb
        ,'provides'
        ,('{
            "pg_safer_settings": {
                "file": "pg_safer_settings--0.6.0.sql",
                "version": "' || pg_safer_settings_version() || '",
                "docfile": "README.md"
            }
        }')::jsonb
        ,'resources'
        ,'{
            "homepage": "https://blog.bigsmoke.us/tag/pg_safer_settings",
            "bugtracker": {
                "web": "https://github.com/bigsmoke/pg_safer_settings/issues"
            },
            "repository": {
                "url": "https://github.com/bigsmoke/pg_safer_settings.git",
                "web": "https://github.com/bigsmoke/pg_safer_settings",
                "type": "git"
            }
        }'::jsonb
        ,'meta-spec'
        ,'{
            "version": "1.0.0",
            "url": "https://pgxn.org/spec/"
        }'::jsonb
        ,'generated_by'
        ,'`select pg_safer_settings_meta_pgxn()`'
        ,'tags'
        ,array[
            'configuration',
            'function',
            'functions',
            'plpgsql',
            'settings',
            'trigger'
        ]
    );
