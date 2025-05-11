-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION pg_safer_settings" to load this file. \quit


/**
 * CHANGELOG.md:
 *
 * - `comment on function pg_safer_settings_table__mirror_col_to_db_role_setting()`
 *   was changed to have the first paragraph on a single line, to play nicer
 *   with everything that is _not_ `pg_readme`.
 */
comment on function pg_safer_settings_table__mirror_col_to_db_role_setting() is
$markdown$If, for some reason, you find it useful to keep a configuration column value synced to a database/role-level setting, this trigger function has your back.

For the opposite requirement—to enforce equality of a configuration column
value to a database (role) setting—, see the
`pg_safer_settings_table__col_must_mirror_db_role_setting()` trigger function.
$markdown$;
