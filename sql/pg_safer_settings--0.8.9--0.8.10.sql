-- Complain if script is sourced in `psql`, rather than via `CREATE EXTENSION`.
\echo Use "CREATE EXTENSION pg_safer_settings" to load this file. \quit


/**
 * CHANGELOG.md:
 *
 * - The technical characteristics and design choices of the behavior of the
 *   `pg_safer_settings_table` table are now extensively documented.
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

The above will cause a table to be created, with the following characteristics:

- The new configuration table will be called `cfg`, because `'cfg'` is the
  default value for the `pg_safer_settings_table.table_name` column.
- The new table will be singleton table, in that it can have only one row, which
  is enforced by the constraints on the new table's `is_singleton` column.

Storing each setting as a separate column instead of as rows has a number of
advantages:

1. A column can have any type.  (Alternatively, we _could_ add a type hint for
   the `text` values that would typically be stored in a row-based schema and
   then use that type hint for the return value of the getter functions.)
2. Columns can have column constraints, or be part of a multi-column constraint.
3. It's easier to write triggers if you don't have to worry which row contains
   the particular setting that the trigger function is involved with.  When
   storing settings as rows, it becomes even more cumbersome if you need to
   deal with inter-setting trigger magic.
4. When settings are stored as columns, it's easy to add generated/computed
   columns, which provide an alternative view of a setting or combine multiple
   settings.
5. It's easy to provide defaults for settings, because these are simply the
   columns' defaults.
6. `NOT NULL` constraints, like all constraints, become easier.

The disadvantage of dividing settings over columns rather than rows is:

1. If you need/want to do concurrent updates, you may run into lock contention.
$md$;
