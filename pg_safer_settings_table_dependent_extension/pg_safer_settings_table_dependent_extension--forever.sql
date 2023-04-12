-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION pg_safer_settings_table_dependent_extension" to load this file. \quit

--------------------------------------------------------------------------------------------------------------

insert into pg_safer_settings_table (
    table_name
    ,owning_extension_name
)
values (
    'subextension_cfg'
    ,'pg_safer_settings_table_dependent_extension'
)
;

alter table subextension_cfg
    add column subext_number_setting int
    ,add column subext_text_setting text
    ,add column subext_bool_setting bool;


update subextension_cfg
    set subext_number_setting = 4
        ,subext_text_setting = 'quite the thing'
        ,subext_bool_setting = true;

--------------------------------------------------------------------------------------------------------------
