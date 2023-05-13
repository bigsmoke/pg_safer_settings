---
pg_extension_name: pg_safer_settings
pg_extension_version: 0.8.9
pg_readme_generated_at: 2023-05-13 15:54:12.098419+01
pg_readme_version: 0.6.3
---

# The `pg_safer_settings` PostgreSQL extension

`pg_safer_settings` provides a handful of functions and mechanisms to make
dealing with settings in Postgres a bit … safer.

## Rationalization and usage patterns

Out of the box, PostgreSQL offers [a
mechanism](#rehashing-how-settings-work-in-postgresql) for custom settings, but
with a couple of caveats:

1. Every `ROLE` can read (`SHOW`) most settings.
2. Every `ROLE` can override (`SET`) most settings for the current session or
   transaction.
3. There is no type checking for settings; they are text values; you may not
   discover that they are faulty until you read them.

Indeed, it is not possible to define a custom setting with restricted access.

### Forcing settings for databases or roles

Let's first look at limitation ② that any `ROLE` can override a
`current_setting()`, even though an administrator may wish to force a
database-wide setting value or force a specific value for a specific role.

dba.stackexchange.com is filled with questions from users trying to do just
that.  They try something like the following:

```sql
ALTER DATABASE mydb
    SET app.settings.bla = 'blegh';
ALTER ROLE myrole
    IN DATABASE mydb
    SET app.settings.bla TO DEFAULT;
```

\[See the [`ALTER
ROLE`](https://www.postgresql.org/docs/current/sql-alterrole.html) and [`ALTER
DATABASE`](https://www.postgresql.org/docs/current/sql-alterdatabase.html)
documentation for details and possibilities of the syntax.]

The problem is that setting the configuration values in that way only changes
the _defaults_.  These defaults can be changed by the user (in this case
`myrole`):

```sql
-- To change for the duration of the session:
SET app.settings.bla = 'blegherrerbypass';  -- or:
SELECT set_config('app.settings.bla', 'blegherrerbypass', false);

-- To change for the duration of the transaction:
SET LOCAL app.settings.bla = 'blegherrerbypass';  -- or:
SELECT set_config('app.settings.bla', 'blegherrerbypass', true);
```

The workaround is to _ignore_ such setting overrides that are local to
transactions or sessions.  To that end, `pg_safer_settings` provides the
`pg_db_setting()` function, which reads the setting value directly from
Postgres its `pg_db_role_settings` catalog, thereby bypassing clever hacking
attempts.

`pg_db_setting()` does not resolve caveat ① or ③—the fact that settings are
world-readable and plain text, respectively.

### Type-safe, read-restricted settings

To maintain settings that are type-safe and can be read/write-restricted _per_
setting, `pg_safer_settings` offers the ability to create and maintain your own
configuration tables.  Please note that these are _not_ your average settings
table that tend to come with all kinds of SQL-ignorant frameworks.  The
configuration tables made by `pg_safer_settings` are singletons, and stores
their settings in columns, _not_ rows.  You as the DB designer add columns, and
the triggers on the table maintain an `IMMUTABLE` function for you with the
current column value (except if you want the value to be secret).  See the
[`pg_safer_settings_table`](#table-pg_safer_settings_table) documentation for
details.

## Rehashing how settings work in PostgreSQL

| Command  | Function                             |
| -------- | ------------------------------------ |
| `SET`    | `set_config(text, text, bool)`       |
| `SHOW`   | `current_setting(text, text, bool)`  |

## The origins of `pg_safer_settings`

`pg_safer_settings` was spun off from the PostgreSQL backend of FlashMQ.com—the
[scalable MQTT hosting service](https://www.flashmq.com/) that supports
millions of concurrent MQTT connections.  Its release as a separate extension
was part of a succesfull effort to modularize the FlashMQ.com PostgreSQL schemas
and, in so doing:

  - reduce and formalize the interdepencies between parts of the system;
  - let the public gaze improve the discipline around testing, documentation
    and other types of polish; and
  - share the love back to the open source / free software community.

## Authors and contributors

* [Rowan](https://www.bigsmoke.us/) originated this extension in 2022 while
  developing the PostgreSQL backend for the [FlashMQ SaaS MQTT cloud
  broker](https://www.flashmq.com/).  Rowan does not like to see himself as a
  tech person or a tech writer, but, much to his chagrin, [he
  _is_](https://blog.bigsmoke.us/category/technology). Some of his chagrin
  about his disdain for the IT industry he poured into a book: [_Why
  Programming Still Sucks_](https://www.whyprogrammingstillsucks.com/).  Much
  more than a “tech bro”, he identifies as a garden gnome, fairy and ork rolled
  into one, and his passion is really to [regreen and reenchant his
  environment](https://sapienshabitat.com/).  One of his proudest achievements
  is to be the third generation ecological gardener to grow the wild garden
  around his beautiful [family holiday home in the forest of Norg, Drenthe,
  the Netherlands](https://www.schuilplaats-norg.nl/) (available for rent!).

## Object reference

### Tables

There are 1 tables that directly belong to the `pg_safer_settings` extension.

#### Table: `pg_safer_settings_table`

Insert a row in `pg_safer_settings_table` to have its triggers automatically create _your_ configuration table, plus the requisite triggers that create and replace the `current_<cfg_column>()` functions as needed.

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

The `pg_safer_settings_table` table has 8 attributes:

1. `pg_safer_settings_table.table_regclass` `regclass`

   - `NOT NULL`
   - `PRIMARY KEY (table_regclass)`

2. `pg_safer_settings_table.table_schema` `name`

   - `NOT NULL`
   - `DEFAULT CURRENT_SCHEMA`

3. `pg_safer_settings_table.table_name` `name`

   - `NOT NULL`
   - `DEFAULT 'cfg'::name`

4. `pg_safer_settings_table.setting_getter_prefix` `name`

   The automatically created/replaced setting getter functions will be named by prepending `setting_getter_prefix` to the column name for that setting.

   The default value (`'current_'`) of the `setting_getter_prefix` follows the
   naming of Postgres its own `current_setting()` function name.

   - `NOT NULL`
   - `DEFAULT 'current_'::name`

5. `pg_safer_settings_table.secret_setting_prefix` `name`

   When a setting's column name starts with the `secret_setting_prefix`, its automatically generated getter function will be a `STABLE` function that, when called, looks up the column value in the table rather than the default `IMMUTABLE` function (with the configuration value cached in the `RETURN` clause) that would otherwise have been created.

   The reason for this is that the schema for functions can be retrieved by
   everyone, and thus any role would be able to read the secret value even if that
   role has not been granted `SELECT` privileges on the column (nor `EXECUTE`
   access to the `IMMUTABLE` function).

   - `NOT NULL`
   - `DEFAULT 'secret_'::name`

6. `pg_safer_settings_table.pg_safer_settings_version` `text`

   - `NOT NULL`
   - `DEFAULT pg_safer_settings_version()`

7. `pg_safer_settings_table.owning_extension_name` `name`

   The name of the extension that registered a specific settings table.

   Make sure that this column contains the name of your extension if your extension inserts a `pg_safer_settings_table` through its set up scripts.

8. `pg_safer_settings_table.owning_extension_version` `text`

   The version of the extension that registered a specific settings table.

   This version is set automatically by the `pg_safer_settings_table__register()`
   trigger function.

### Routines

#### Function: `pg_db_setting (text, regrole)`

`pg_db_setting()` allows you to look up a setting value as `SET` for a `DATABASE` or `ROLE`, ignoring the local (transaction or session) value for that setting.

Example:

```sql
CREATE DATABASE mydb;
CONNECT TO mydb
CREATE ROLE myrole;
ALTER DATABASE mydb
    SET app.settings.bla = 1::text;
ALTER ROLE myrole
    IN DATABASE mydb
    SET app.settings.bla = 2::text;
SET ROLE myrole;
SET app.settings.bla TO 3::text;
SELECT current_setting('app.settings.bla', true);  -- '3'
SELECT pg_db_role_setting('app.settings.bla');  -- '1'
SELECT pg_db_role_setting('app.settings.bla', current_user);  -- '2'
```

Function arguments:

| Arg. # | Arg. mode  | Argument name                                                     | Argument type                                                        | Default expression  |
| ------ | ---------- | ----------------------------------------------------------------- | -------------------------------------------------------------------- | ------------------- |
|   `$1` |       `IN` | `pg_setting_name$`                                                | `text`                                                               |  |
|   `$2` |       `IN` | `pg_role$`                                                        | `regrole`                                                            | `0` |

Function return type: `text`

Function attributes: `STABLE`

#### Function: `pg_safer_settings_meta_pgxn()`

Returns the JSON meta data that has to go into the `META.json` file needed for PGXN—PostgreSQL Extension Network—packages.

The `Makefile` includes a recipe to allow the developer to: `make META.json` to
refresh the meta file with the function's current output, including the
`default_version`.

And indeed, `pg_safer_settings` can be found on PGXN:
https://pgxn.org/dist/pg_safer_settings/

Function return type: `jsonb`

Function attributes: `STABLE`

#### Function: `pg_safer_settings_readme()`

This function utilizes the `pg_readme` extension to generate a thorough README for this extension, based on the `pg_catalog` and the `COMMENT` objects found therein.

Function return type: `text`

Function-local settings:

  *  `SET search_path TO ext, ext, pg_temp`
  *  `SET pg_readme.include_view_definitions TO true`
  *  `SET pg_readme.include_routine_definitions_like TO {test__%}`

#### Function: `pg_safer_settings_table__col_must_mirror_current_setting()`

If you want to forbid changing a configuration table column value to something that is not in sync with the current value of the given setting, use this trigger function.

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

Function return type: `trigger`

Function-local settings:

  *  `SET search_path TO ext, ext, pg_temp`

#### Function: `pg_safer_settings_table__col_must_mirror_db_role_setting()`

If you want to forbid changing a configuration table column value to something that is not in sync with the given setting (for the optionally given `ROLE`) `SET` on the `DATABASE` level, this trigger function is your friend.

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

Function return type: `trigger`

Function-local settings:

  *  `SET search_path TO ext, ext, pg_temp`

#### Function: `pg_safer_settings_table_columns (name, name)`

Function arguments:

| Arg. # | Arg. mode  | Argument name                                                     | Argument type                                                        | Default expression  |
| ------ | ---------- | ----------------------------------------------------------------- | -------------------------------------------------------------------- | ------------------- |
|   `$1` |       `IN` | `table_schema$`                                                   | `name`                                                               |  |
|   `$2` |       `IN` | `table_name$`                                                     | `name`                                                               |  |

Function return type: `SETOF information_schema.columns`

Function attributes: `STABLE`, `LEAKPROOF`, `RETURNS NULL ON NULL INPUT`, `PARALLEL SAFE`, ROWS 1000

Function-local settings:

  *  `SET search_path TO ext, ext, pg_temp`
  *  `SET pg_readme.include_this_routine_definition TO true`

```sql
CREATE OR REPLACE FUNCTION ext.pg_safer_settings_table_columns("table_schema$" name, "table_name$" name)
 RETURNS SETOF information_schema.columns
 LANGUAGE sql
 STABLE PARALLEL SAFE STRICT LEAKPROOF
 SET search_path TO 'ext', 'ext', 'pg_temp'
 SET "pg_readme.include_this_routine_definition" TO 'true'
BEGIN ATOMIC
 SELECT columns.table_catalog,
     columns.table_schema,
     columns.table_name,
     columns.column_name,
     columns.ordinal_position,
     columns.column_default,
     columns.is_nullable,
     columns.data_type,
     columns.character_maximum_length,
     columns.character_octet_length,
     columns.numeric_precision,
     columns.numeric_precision_radix,
     columns.numeric_scale,
     columns.datetime_precision,
     columns.interval_type,
     columns.interval_precision,
     columns.character_set_catalog,
     columns.character_set_schema,
     columns.character_set_name,
     columns.collation_catalog,
     columns.collation_schema,
     columns.collation_name,
     columns.domain_catalog,
     columns.domain_schema,
     columns.domain_name,
     columns.udt_catalog,
     columns.udt_schema,
     columns.udt_name,
     columns.scope_catalog,
     columns.scope_schema,
     columns.scope_name,
     columns.maximum_cardinality,
     columns.dtd_identifier,
     columns.is_self_referencing,
     columns.is_identity,
     columns.identity_generation,
     columns.identity_start,
     columns.identity_increment,
     columns.identity_maximum,
     columns.identity_minimum,
     columns.identity_cycle,
     columns.is_generated,
     columns.generation_expression,
     columns.is_updatable
    FROM information_schema.columns
   WHERE (((columns.table_schema)::name = pg_safer_settings_table_columns."table_schema$") AND ((columns.table_name)::name = pg_safer_settings_table_columns."table_name$") AND (NOT ((columns.column_name)::name = ANY (ARRAY['is_singleton'::text, 'inserted_at'::text, 'updated_at'::text]))));
END
```

#### Function: `pg_safer_settings_table__create_or_replace_getters()`

This trigger function automatically `CREATE OR REPLACE`s, for each configuration column in the table that it is attached to: a function that returns the current value for that column.

The created function will have the same name as the column it wraps, prefixed
with the `setting_getter_prefix` from the
[`pg_safer_settings_table`](#table-pg_safer_settings_table).

Normally, the created function will be `IMMUTABLE` and return a hard-coded copy
of the lastest configuration value, except if the column name it reflects
starts with the `secret_setting_prefix` from the
[`pg_safer_settings_table`](#table-pg_safer_settings_table)—then the function
will be a `STABLE` function that, upon invocation, retrieves the value from the
configuration table.

`SELECT` privileges on the setting columns are translated into `EXECUTE`
permissions on the wrapper functions.

Function return type: `trigger`

Function-local settings:

  *  `SET search_path TO ext, ext, pg_temp`

#### Function: `pg_safer_settings_table__mirror_col_to_db_role_setting()`

If, for some reason, you find it useful to keep a configuration column value synced to a database/role-level setting, this trigger function has your back.

For the opposite requirement—to enforce equality of a configuration column
value to a database (role) setting—, see the
`pg_safer_settings_table__col_must_mirror_db_role_setting()` trigger function.

Function return type: `trigger`

Function-local settings:

  *  `SET search_path TO ext, ext, pg_temp`

#### Function: `pg_safer_settings_table__register()`

This trigger function creates and maintains the safer settings tables that are registered with it.

Function return type: `trigger`

Function-local settings:

  *  `SET search_path TO ext, ext, pg_temp`

#### Function: `pg_safer_settings_table__update_on_copy()`

`UPDATE` instead of `INSERT` when triggered from a `COPY FROM STDIN` statement.

Without this trigger, when another extension sets up a
`pg_safer_settings_table` from one of its setup scripts, `pg_restore` will
crash, because it would try to `INSERT` _twice_:

1. as a result of the `INSERT AFTER` trigger on `pg_safer_settings_table`, _and_
2. as a result of the contents of the created settings table always being
   included in the `pg_dump`.  Because you want to remember your settings, right?

Function return type: `trigger`

Function-local settings:

  *  `SET search_path TO ext, ext, pg_temp`

#### Function: `pg_safer_settings_version()`

Returns the currently (being) installed version of the `pg_safer_settings` extension.

Function return type: `text`

Function attributes: `STABLE`, `LEAKPROOF`, `PARALLEL SAFE`

#### Procedure: `test_dump_restore__pg_safer_settings_table (text)`

Procedure arguments:

| Arg. # | Arg. mode  | Argument name                                                     | Argument type                                                        | Default expression  |
| ------ | ---------- | ----------------------------------------------------------------- | -------------------------------------------------------------------- | ------------------- |
|   `$1` |       `IN` | `test_stage$`                                                     | `text`                                                               |  |

Procedure-local settings:

  *  `SET search_path TO ext, ext, pg_temp`
  *  `SET plpgsql.check_asserts TO true`
  *  `SET pg_readme.include_this_routine_definition TO true`

```sql
CREATE OR REPLACE PROCEDURE ext.test_dump_restore__pg_safer_settings_table(IN "test_stage$" text)
 LANGUAGE plpgsql
 SET search_path TO 'ext', 'ext', 'pg_temp'
 SET "plpgsql.check_asserts" TO 'true'
 SET "pg_readme.include_this_routine_definition" TO 'true'
AS $procedure$
declare
    _cfg_record record;
begin
    assert test_stage$ in ('pre-dump', 'post-restore');

    if test_stage$ = 'pre-dump' then
        insert into pg_safer_settings_table (table_name) values ('test__cfg');
        alter table test__cfg
            add boolean_test_setting bool
                not null
                default false
            ,add secret_test_setting text
        ;
        update test__cfg
            set secret_test_setting = 'Th1s1ss3cr3t'
        ;

        create extension pg_safer_settings_table_dependent_extension;
        assert current_subext_number_setting() = 4;
        update subextension_cfg set subext_number_setting = 5;
        assert current_subext_number_setting() = 5;

        create extension pg_safer_settings_table_dependent_subextension;
        assert current_subext_text_setting() = 'Set by subsubextension';

    elsif test_stage$ = 'post-restore' then
        select * into strict _cfg_record from test__cfg;

        assert _cfg_record.boolean_test_setting = false;
        assert current_boolean_test_setting() = false;

        assert _cfg_record.secret_test_setting = 'Th1s1ss3cr3t';
        assert current_secret_test_setting() = 'Th1s1ss3cr3t';

        assert to_regprocedure('current_boolean_test_setting()') is not null;
        assert to_regprocedure('current_secret_test_setting()') is not null;

        delete from pg_safer_settings_table where table_name = 'test__cfg';

        assert to_regprocedure('current_boolean_test_setting()') is null;
        assert to_regprocedure('current_secret_test_setting()') is null;

        assert current_subext_number_setting() = 5,
            'The configaration value set _after_ `CREATE EXTENSION` should have been preserved.';
        assert current_subext_bool_setting() = true;

        assert current_subext_text_setting() = 'Set by subsubextension',
            'The configuration value set by the subsubextension should have been preserver.';
    end if;
end;
$procedure$
```

#### Procedure: `test__pg_db_setting()`

This routine tests the `pg_db_setting()` function.

The routine name is compliant with the `pg_tst` extension. An intentional
choice has been made to not _depend_ on the `pg_tst` extension its test runner
or developer-friendly assertions to keep the number of inter-extension
dependencies to a minimum.

Procedure-local settings:

  *  `SET search_path TO ext, ext, pg_temp`
  *  `SET plpgsql.check_asserts TO true`
  *  `SET pg_readme.include_this_routine_definition TO true`

```sql
CREATE OR REPLACE PROCEDURE ext.test__pg_db_setting()
 LANGUAGE plpgsql
 SET search_path TO 'ext', 'ext', 'pg_temp'
 SET "plpgsql.check_asserts" TO 'true'
 SET "pg_readme.include_this_routine_definition" TO 'true'
AS $procedure$
begin
    execute 'ALTER DATABASE ' || current_database()
        || ' SET pg_safer_settings.test_pg_db_setting = ''foo''';
    assert pg_db_setting('pg_safer_settings.test_pg_db_setting') = 'foo';

    set pg_safer_settings.settings.test_pg_db_setting = 'bar';
    assert pg_db_setting('pg_safer_settings.test_pg_db_setting') = 'foo';

    assert pg_db_setting('pg_safer_settings.unknown_setting') is null;

    create role __test_role;
    execute 'ALTER ROLE __test_role IN DATABASE ' || current_database()
        || ' SET pg_safer_settings.test_pg_db_setting = ''foobar''';
    assert pg_db_setting('pg_safer_settings.test_pg_db_setting', '__test_role') = 'foobar';
    assert pg_db_setting('pg_safer_settings.test_pg_db_setting') = 'foo';

    raise transaction_rollback;
exception
    when transaction_rollback then
end;
$procedure$
```

#### Procedure: `test__pg_safer_settings_table()`

Procedure-local settings:

  *  `SET search_path TO ext, ext, pg_temp`
  *  `SET pg_readme.include_this_routine_definition TO true`

```sql
CREATE OR REPLACE PROCEDURE ext.test__pg_safer_settings_table()
 LANGUAGE plpgsql
 SET search_path TO 'ext', 'ext', 'pg_temp'
 SET "pg_readme.include_this_routine_definition" TO 'true'
AS $procedure$
declare
    _pg_safer_settings_table pg_safer_settings_table;
    _cfg_record record;
begin
    insert into pg_safer_settings_table
        (table_name)
    values
        ('test__cfg')
    returning
        *
    into
        _pg_safer_settings_table
    ;
    assert _pg_safer_settings_table.setting_getter_prefix = 'current_';

    select * into _cfg_record from test__cfg;
    assert _cfg_record.is_singleton;

    alter table test__cfg
        add boolean_test_setting bool
            not null
            default false;
    update test__cfg
        set boolean_test_setting = default;

    select * into _cfg_record from test__cfg;
    assert _cfg_record.boolean_test_setting = false;
    assert current_boolean_test_setting() = false;
    assert (
        select
            provolatile = 'i'
        from
            pg_proc
        where
            pronamespace = current_schema::regnamespace
            and proname = 'current_boolean_test_setting'
    );

    alter table test__cfg
        add secret_test_setting text;
    update test__cfg
        set secret_test_setting = 'Th1s1ss3cr3t';
    assert current_secret_test_setting() = 'Th1s1ss3cr3t';
    assert (
        select
            provolatile = 's'
        from
            pg_proc
        where
            pronamespace = current_schema::regnamespace
            and proname = 'current_secret_test_setting'
    );

    delete from pg_safer_settings_table where table_name = 'test__cfg';

    raise transaction_rollback;
exception
    when transaction_rollback then
end;
$procedure$
```

## Colophon

This `README.md` for the `pg_safer_settings` extension was automatically generated using the [`pg_readme`](https://github.com/bigsmoke/pg_readme) PostgreSQL extension.
