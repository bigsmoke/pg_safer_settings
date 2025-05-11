-- Complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION pg_safer_settings" to load this file. \quit


/**
 * CHANGELOG.md:
 *
 * - A `CHECK` constraint was added to `pg_safer_settings_table` to enforce
 *   that either the `owning_extension_name` and `owning_extension_version`
 *   columns are both null or neither of them are null.
 */
alter table pg_safer_settings_table
    add check ((owning_extension_name is null) = (owning_extension_version is null));


/**
 * CHANGELOG.md:
 *
 * - The `pg_safer_settings_readme()` function now installs the `pg_readme`
 *   extension `WITH CASCADE`, in case that its `hstore` dependency is also
 *   not already installed while the function is running.
 */
create or replace function pg_safer_settings_readme()
    returns text
    volatile
    set search_path from current
    set pg_readme.include_view_definitions to 'true'
    set pg_readme.include_routine_definitions_like to '{test__%}'
    language plpgsql
    as $plpgsql$
declare
    _readme text;
begin
    create extension if not exists pg_readme
        with cascade;

    _readme := pg_extension_readme('pg_safer_settings'::name);

    raise transaction_rollback;  -- to `DROP EXTENSION` if we happened to `CREATE EXTENSION` for just this.
exception
    when transaction_rollback then
        return _readme;
end;
$plpgsql$;


/**
 * CHANGELOG.md:
 *
 * - Some `COMMENT`s were improved and cleaned up, so that:
 *
 *   + the first (synopsis) paragraph is always on one line,
 *   + which is also the first line of the `comment`, and
 *   + there are no links on that line;
 *
 *   This concerned the `COMMENT`s:
 *
 *   1. `on function pg_safer_settings_readme()`;
 */
comment on function pg_safer_settings_readme() is
$md$This function utilizes the `pg_readme` extension to generate a thorough README for this extension, based on the `pg_catalog` and the `COMMENT` objects found therein.
$md$;


/**
 * CHANGELOG.md:
 *
 *   2. `on function pg_safer_settings_meta_pgxn()`, which also had some
 *      punctuation fixed;
 */
comment on function pg_safer_settings_meta_pgxn() is
$md$Returns the JSON meta data that has to go into the `META.json` file needed for PGXN—PostgreSQL Extension Network—packages.

The `Makefile` includes a recipe to allow the developer to: `make META.json` to
refresh the meta file with the function's current output, including the
`default_version`.

And indeed, `pg_safer_settings` can be found on PGXN:
https://pgxn.org/dist/pg_safer_settings/
$md$;


/**
 * CHANGELOG.md:
 *
 *   3. `on table pg_safer_settings_table`;
 */
comment on table pg_safer_settings_table is
$md$Insert a row in `pg_safer_settings_table` to have its triggers automatically create _your_ configuration table, plus the requisite triggers that create and replace the `current_<cfg_column>()` functions as needed.

`pg_safer_settings_table` has default for all its columns.  In the simplest
form, you can do a default-only insert:

```sql
CREATE SCHEMA ext;
CREATE SCHEMA myschema;
SET search_path TO myschema, ext;

CREATE EXTENSION pg_safer_settings WITH SCHEMA ext;

INSERT INTO ext.pg_safer_settings_table DEFAULT VALUES
    RETURNING *;
```
$md$;


/**
 * CHANGELOG.md:
 *
 *   4. `on column pg_safer_settings_table.secret_setting_prefix`;
 */
comment on column pg_safer_settings_table.secret_setting_prefix is
$md$When a setting's column name starts with the `secret_setting_prefix`, its automatically generated getter function will be a `STABLE` function that, when called, looks up the column value in the table rather than the default `IMMUTABLE` function (with the configuration value cached in the `RETURN` clause) that would otherwise have been created.

The reason for this is that the schema for functions can be retrieved by
everyone, and thus any role would be able to read the secret value even if that
role has not been granted `SELECT` privileges on the column (nor `EXECUTE`
access to the `IMMUTABLE` function).
$md$;


/**
 * CHANGELOG.md:
 *
 *   5. `on function pg_safer_settings_table__col_must_mirror_current_setting()`; and
 */
comment on function pg_safer_settings_table__col_must_mirror_current_setting() is
$md$If you want to forbid changing a configuration table column value to something that is not in sync with the current value of the given setting, use this trigger function.

Use it as a constraint trigger:

```sql
create constraint trigger must_mirror_db_role_setting__max_plumbus_count
    after insert or update on your.cfg
    for each row
    execute function safer_settings_table__col_must_mirror_db_role_setting(
        'max_plumbus_count',
        'app.settings.max_plumbus_count'
    );
```
$md$;


/**
 * CHANGELOG.md:
 *
 *   6. `on function pg_safer_settings_table__col_must_mirror_db_role_setting()`;
 */
comment on function pg_safer_settings_table__col_must_mirror_db_role_setting() is
$md$If you want to forbid changing a configuration table column value to something that is not in sync with the given setting (for the optionally given `ROLE`) `SET` on the `DATABASE` level, this trigger function is your friend.

Use it as a constraint trigger:

```sql
create constraint trigger must_mirror_db_role_setting__deployment_tier
    after insert or update on your.cfg
    for each row
    execute function safer_settings_table__col_must_mirror_db_role_setting(
        'deployment_tier',
        'app.settings.deployment_tier'
    );
```

Alternatively, you may wish to `SET` the PostgreSQL setting automatically
whenever the column is `UPDATE`d. In that case, use the
`pg_safer_settings_table__mirror_col_to_db_role_setting()` trigger function
instead.

Note that there is _no way_—not even using event triggers—to automatically
catch configuration changes as the `ALTER DATABASE` level as they happen.
Triggers using this function will only catch incompatibilities when the trigger
is … triggered.
$md$;
