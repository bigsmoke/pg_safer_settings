begin;

create extension pg_safer_settings cascade;

call test__pg_db_setting();
call test__pg_safer_settings_table();

rollback;
