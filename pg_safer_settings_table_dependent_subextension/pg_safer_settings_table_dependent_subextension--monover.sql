-- Complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION pg_safer_settings_table_dependent_subextension" to load this file. \quit

--------------------------------------------------------------------------------------------------------------

update
    subextension_cfg
set
    subext_text_setting = 'Set by subsubextension'
;

--------------------------------------------------------------------------------------------------------------
