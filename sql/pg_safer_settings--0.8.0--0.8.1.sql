-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION pg_safer_settings" to load this file. \quit

--------------------------------------------------------------------------------------------------------------

comment on function pg_safer_settings_table__mirror_col_to_db_role_setting() is
$markdown$If, for some reason, you find it useful to keep a configuration column value synced to a database/role-level setting, this trigger function has your back.

For the opposite requirement—to enforce equality of a configuration column
value to a database (role) setting—, see the
`pg_safer_settings_table__col_must_mirror_db_role_setting()` trigger function.
$markdown$;

--------------------------------------------------------------------------------------------------------------
