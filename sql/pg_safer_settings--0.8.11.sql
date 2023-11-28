-- Complain if script is sourced in `psql`, rather than via `CREATE EXTENSION`.
\echo Use "CREATE EXTENSION pg_safer_settings" to load this file. \quit

--------------------------------------------------------------------------------------------------------------

comment on extension pg_safer_settings is $markdown$
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

<?pg-readme-reference?>

<?pg-readme-colophon?>
$markdown$;

--------------------------------------------------------------------------------------------------------------

create function pg_safer_settings_readme()
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

comment on function pg_safer_settings_readme() is
$md$This function utilizes the `pg_readme` extension to generate a thorough README for this extension, based on the `pg_catalog` and the `COMMENT` objects found therein.
$md$;

--------------------------------------------------------------------------------------------------------------

create function pg_safer_settings_version()
    returns text
    stable
    leakproof
    parallel safe
    return (
        select
            pg_extension.extversion
        from
            pg_catalog.pg_extension
        where
            pg_extension.extname = 'pg_safer_settings'
    );

comment on function pg_safer_settings_version() is
$md$Returns the currently (being) installed version of the `pg_safer_settings` extension.
$md$;

--------------------------------------------------------------------------------------------------------------

-- Bump entry version.
create function pg_safer_settings_meta_pgxn()
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
                "file": "pg_safer_settings--0.8.11.sql",
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

comment on function pg_safer_settings_meta_pgxn() is
$md$Returns the JSON meta data that has to go into the `META.json` file needed for PGXN—PostgreSQL Extension Network—packages.

The `Makefile` includes a recipe to allow the developer to: `make META.json` to
refresh the meta file with the function's current output, including the
`default_version`.

And indeed, `pg_safer_settings` can be found on PGXN:
https://pgxn.org/dist/pg_safer_settings/
$md$;

--------------------------------------------------------------------------------------------------------------

create function pg_db_setting(pg_setting_name$ text, pg_role$ regrole = 0)
    returns text
    stable
--    security definer
    return (
        select
            regexp_replace(expanded_settings.raw_setting, E'^[^=]+=', '')
        from
            pg_catalog.pg_db_role_setting
        inner join
            pg_catalog.pg_database
            on pg_database.oid = pg_db_role_setting.setdatabase
        cross join lateral
            unnest(pg_db_role_setting.setconfig) as expanded_settings(raw_setting)
        where
            pg_database.datname = current_database()
            and pg_db_role_setting.setrole = coalesce(
                pg_role$,
                0  -- 0 means “not role-specific”
            )
            and expanded_settings.raw_setting like pg_setting_name$ || '=%'
        limit 1
    );

comment on function pg_db_setting(text, regrole) is
$md$`pg_db_setting()` allows you to look up a setting value as `SET` for a `DATABASE` or `ROLE`, ignoring the local (transaction or session) value for that setting.

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
$md$;

--------------------------------------------------------------------------------------------------------------

create procedure test__pg_db_setting()
    set search_path from current
    set plpgsql.check_asserts to true
    set pg_readme.include_this_routine_definition to true
    language plpgsql
    as $$
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
$$;

comment on procedure test__pg_db_setting() is
$md$This routine tests the `pg_db_setting()` function.

The routine name is compliant with the `pg_tst` extension. An intentional
choice has been made to not _depend_ on the `pg_tst` extension its test runner
or developer-friendly assertions to keep the number of inter-extension
dependencies to a minimum.
$md$;

--------------------------------------------------------------------------------------------------------------

create table pg_safer_settings_table (
    table_regclass regclass
        primary key
    ,table_schema name
        not null
        default current_schema
    ,table_name name
        not null
        default 'cfg'
    ,unique (table_schema, table_name)
    ,setting_getter_prefix name
        not null
        default 'current_'
    ,secret_setting_prefix name
        not null
        default 'secret_'
    ,pg_safer_settings_version text
        not null
        default pg_safer_settings_version()
    ,owning_extension_name name
    ,owning_extension_version text
    ,check ((owning_extension_name is null) = (owning_extension_version is null))
);

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

comment on column pg_safer_settings_table.setting_getter_prefix is
$md$The automatically created/replaced setting getter functions will be named by prepending `setting_getter_prefix` to the column name for that setting.

The default value (`'current_'`) of the `setting_getter_prefix` follows the
naming of Postgres its own `current_setting()` function name.
$md$;

comment on column pg_safer_settings_table.secret_setting_prefix is
$md$When a setting's column name starts with the `secret_setting_prefix`, its automatically generated getter function will be a `STABLE` function that, when called, looks up the column value in the table rather than the default `IMMUTABLE` function (with the configuration value cached in the `RETURN` clause) that would otherwise have been created.

The reason for this is that the schema for functions can be retrieved by
everyone, and thus any role would be able to read the secret value even if that
role has not been granted `SELECT` privileges on the column (nor `EXECUTE`
access to the `IMMUTABLE` function).
$md$;

comment on column pg_safer_settings_table.owning_extension_name is
$md$The name of the extension that registered a specific settings table.

Make sure that this column contains the name of your extension if your extension inserts a `pg_safer_settings_table` through its set up scripts.
$md$;

comment on column pg_safer_settings_table.owning_extension_version is
$md$The version of the extension that registered a specific settings table.

This version is set automatically by the `pg_safer_settings_table__register()`
trigger function.
$md$;

select pg_catalog.pg_extension_config_dump(
    'pg_safer_settings_table'
    ,'WHERE owning_extension_name IS NULL'
);

--------------------------------------------------------------------------------------------------------------

create function pg_safer_settings_table__register()
    returns trigger
    set search_path from current
    language plpgsql
    as $$
declare
    _current_table_schema name;
    _current_table_name name;
    _col_name name;
    _copying bool;
begin
    assert tg_when in ('BEFORE', 'AFTER');
    assert tg_level = 'ROW';
    assert tg_op in ('INSERT', 'UPDATE', 'DELETE');
    assert tg_table_schema = current_schema;
    assert tg_table_name = 'pg_safer_settings_table';
    assert tg_nargs = 0;

    -- When we are inside a `COPY` command, it is likely that we're restoring from a `pg_dump`.
    -- Otherwise, why would you want to bulk insert into such a small table?
    _copying := tg_op = 'INSERT' and exists (
        select from
            pg_stat_progress_copy
        where
            relid = tg_relid
            and command = 'COPY FROM'
            and type = 'PIPE'
    );

    if tg_op = 'INSERT' and tg_when = 'BEFORE' and _copying then
        -- Make sure we don't keep using the pre-`pg_dump` OID.
        NEW.table_regclass := (NEW.table_schema || '.' || NEW.table_name)::regclass;

    elsif tg_op = 'INSERT' and tg_when = 'BEFORE' and not _copying then
        if NEW.table_regclass is not null or exists(
            select
            from
                pg_catalog.pg_class
            where
                pg_class.relnamespace = NEW.table_schema::regnamespace::oid
                and pg_class.relname = NEW.table_name
        )
        then
            raise exception using
                message = format(
                    'The configuration table `%I.%I` already exist.'
                    ,NEW.table_schema, NEW.table_name
                )
                ,detail = format(
                    'But I (`%I` on `%I.%I`) was not triggered by a `COPY` command.'
                    ,tg_name, tg_table_schema, tg_table_name
                )
                ,hint = 'Make sure to never use the `pg_dump --insert` flag.'
                ,schema = tg_table_schema
                ,table = tg_table_name;
        end if;

        execute 'CREATE TABLE ' || quote_ident(NEW.table_schema) || '.' || quote_ident(NEW.table_name) || '('
            || 'is_singleton BOOLEAN NOT NULL DEFAULT TRUE UNIQUE'
            ||  '     CONSTRAINT check_true CHECK (is_singleton = TRUE)'
            || ',inserted_at TIMESTAMPTZ NOT NULL DEFAULT now()'
            || ',updated_at TIMESTAMPTZ NOT NULL DEFAULT now()'
            || ')';

        NEW.table_regclass := (NEW.table_schema || '.' || NEW.table_name)::regclass;

        execute 'COMMENT'
            || ' ON TABLE ' || NEW.table_regclass::text
            || ' IS ''Add your own (typed and constrained!) columns to this table as needed.''';

        execute 'CREATE TRIGGER update_on_copy'
            || ' BEFORE INSERT ON ' || NEW.table_regclass::text
            || ' FOR EACH ROW'
            || ' EXECUTE FUNCTION pg_safer_settings_table__update_on_copy()';

        execute 'CREATE TRIGGER create_or_replace_getters'
            || ' AFTER INSERT OR UPDATE ON ' || NEW.table_regclass::text
            || ' FOR EACH ROW'
            || ' EXECUTE FUNCTION pg_safer_settings_table__create_or_replace_getters()';

        execute 'CREATE TRIGGER no_delete'
            || ' BEFORE DELETE ON ' || NEW.table_regclass::text
            || ' FOR EACH STATEMENT'
            || ' EXECUTE FUNCTION no_delete()';

        execute 'COMMENT ON TRIGGER no_delete ON ' || NEW.table_regclass::text
            || ' IS $markdown$The `no_delete()` trigger function comes from the very unpretentious [`pg_utility_trigger_functions`](https://github.com/bigsmoke/pg_utility_trigger_functions) extension.
$markdown$';

        if NEW.owning_extension_name is not null then
            NEW.owning_extension_version := coalesce(
                NEW.owning_extension_version
                ,(
                    select
                        extversion
                    from
                        pg_catalog.pg_extension
                    where
                        extname = NEW.owning_extension_name
                )
            );

            -- Allow the new settings table to be backed up by `pg_dump`:
            perform pg_catalog.pg_extension_config_dump(NEW.table_regclass, '');
        end if;
    elsif tg_op = 'INSERT' and tg_when = 'AFTER' and not _copying then
        execute 'INSERT INTO ' || NEW.table_regclass::text || ' VALUES (DEFAULT, DEFAULT, DEFAULT)';

    elsif tg_op = 'UPDATE' and tg_when = 'BEFORE' then
        NEW.updated_at := now();

        select
            pg_class.relnamespace::name
            ,pg_class.relname
        from
            pg_catalog.pg_class
        where
            pg_class.oid = NEW.table_regclass
        into
            _current_table_schema
            ,_current_table_name
        ;
        if _current_table_schema != NEW.table_schema then
            raise notice 'Table has been moved from the % schema to %; updating record in % te reflect this.',
                NEW.table_schema, _current_table_schema, tg_table_name;
            NEW.table_schema := _current_table_schema;
        end if;
        if _current_table_name != NEW.table_name then
            raise notice 'Table has been renamed from % to %; updating record in % to reflect this.',
                NEW.table_name, _current_table_name, tg_table_name;
            NEW.table_name := _current_table_name;
        end if;
        if NEW.table_name != OLD.table_name then
            execute 'ALTER TABLE ' || NEW.table_regclass::text || ' RENAME TO ' || NEW.table_name;
        end if;
        if NEW.table_schema != OLD.table_schema then
            execute 'ALTER TABLE ' || NEW.table_regclass::text || ' SET SCHEMA ' || NEW.table_schema;
        end if;
        if NEW.setting_getter_prefix != OLD.setting_getter_prefix then
            raise exception 'Changing `setting_getter_prefix` not supported (yet).';
        end if;
        if NEW.secret_setting_prefix != OLD.secret_setting_prefix then
            raise exception 'Changing `secret_setting_prefix` not supported (yet).';
        end if;

    elsif tg_op = 'DELETE' and tg_when = 'AFTER' then
        for _col_name in
            select
                column_name
            from
                pg_safer_settings_table_columns(OLD.table_schema, OLD.table_name)
        loop
            execute 'DROP FUNCTION ' || quote_ident(OLD.table_schema) || '.'
                || quote_ident(OLD.setting_getter_prefix || _col_name) || '()';
        end loop;
        execute 'DROP TABLE ' || OLD.table_regclass::name;
    end if;

    if tg_op in ('INSERT', 'UPDATE') then
        return NEW;
    end if;
    return OLD;
end;
$$;

comment on function pg_safer_settings_table__register() is
$md$This trigger function creates and maintains the safer settings tables that are registered with it.
$md$;

create trigger before_trigger
    before insert or update or delete on pg_safer_settings_table
    for each row
    execute function pg_safer_settings_table__register();

create trigger after_trigger
    after insert or update or delete on pg_safer_settings_table
    for each row
    execute function pg_safer_settings_table__register();

--------------------------------------------------------------------------------------------------------------

create function pg_safer_settings_table_columns(table_schema$ name, table_name$ name)
    returns setof information_schema.columns
    stable
    returns null on null input
    leakproof
    parallel safe
    set search_path from current
    set pg_readme.include_this_routine_definition to true
    language sql
begin atomic
    select
        columns.*
    from
        information_schema.columns
    where
        columns.table_schema = table_schema$
        and columns.table_name = table_name$
        and not columns.column_name = any (array['is_singleton', 'inserted_at', 'updated_at']);
end;

--------------------------------------------------------------------------------------------------------------

create function pg_safer_settings_table__create_or_replace_getters()
    returns trigger
    set search_path from current
    language plpgsql
    as $$
declare
    _func_name name;
    _func_signature text;
    _func_already_existed bool;
    _func_owning_extension name;
    _col_name name;
    _col_type text;
    _col_no int;
    _val_old text;
    _val_new text;
    _pg_safer_settings_table pg_safer_settings_table;
    _col_privilege information_schema.column_privileges;
    _extension_context_detection_object name;
    _extension_context name;
begin
    assert tg_when = 'AFTER';
    assert tg_level = 'ROW';
    assert tg_op in ('INSERT', 'UPDATE');
    assert tg_relid in (select table_regclass from pg_safer_settings_table);

    -- The extension context may be:
    --    a) outside of a `CREATE EXTENSION` / `ALTER EXTENSION` context (`_extension_context IS NULL`);
    --    b) inside the `CREATE EXTENSION` / `ALTER EXTENSION` context of the extension owning the config
    --       table to which this trigger is attached; or
    --    c) inside the `CREATE EXTENSION` / `ALTER EXTENSION` context of extension that changes settings in
    --       another extension's configuration table.
    _extension_context_detection_object := format(
        'extension_context_detector_%s'
        ,floor(pg_catalog.random() * 1000)
    );
    execute format('CREATE TEMPORARY TABLE %I (col int) ON COMMIT DROP', _extension_context_detection_object);
    select
        pg_extension.extname
    into
        _extension_context
    from
        pg_catalog.pg_depend
    inner join
        pg_catalog.pg_extension
        on pg_extension.oid = pg_depend.refobjid
    where
        pg_depend.classid = 'pg_catalog.pg_class'::regclass
        and pg_depend.objid = _extension_context_detection_object::regclass
        and pg_depend.refclassid = 'pg_catalog.pg_extension'::regclass
    ;
    execute format('DROP TABLE %I', _extension_context_detection_object);

    select
        *
    into
        _pg_safer_settings_table
    from
        pg_safer_settings_table
    where
        pg_safer_settings_table.table_regclass = tg_relid
    ;

    for
        _col_name
        ,_col_type
        ,_col_no
    in select
        columns.column_name
        ,coalesce(
            quote_ident(columns.domain_schema) || '.' || quote_ident(columns.domain_name),
            quote_ident(columns.udt_schema) || '.' || quote_ident(columns.udt_name)
        )
        ,columns.ordinal_position
    from
        pg_safer_settings_table_columns(tg_table_schema, tg_table_name) as columns
    loop
        _func_name := _pg_safer_settings_table.setting_getter_prefix || _col_name;
        _func_signature := quote_ident(tg_table_schema) || '.' || quote_ident(_func_name) || '()';
        _func_already_existed := to_regprocedure(_func_signature) is not null;

        execute format('SELECT %s.%I::TEXT', '$1', _col_name) using NEW into _val_new;
        if tg_op = 'UPDATE' then
            execute format('SELECT %s.%I::TEXT', '$1', _col_name) using OLD into _val_old;
        else
            _val_old := null;
        end if;
        if _val_old is distinct from _val_new
            or to_regproc(quote_ident(tg_table_schema) || '.' || quote_ident(_func_name) || '()') is null
        then
            if (_pg_safer_settings_table.owning_extension_name is not null)
                    and _extension_context is not null
                    and _func_already_existed
            then
                -- Temporarily let the extension that changed the setting steal the wrapper function,
                -- because only the owner of a function can use `CREATE OR REPLACE FUNCTION` on it.
                -- (And we don't want to `DROP FUNCTION`, because the function may have dependents.)
                execute 'ALTER EXTENSION ' || quote_ident(_pg_safer_settings_table.owning_extension_name)
                    || ' DROP FUNCTION ' || _func_signature;
                execute 'ALTER EXTENSION ' || quote_ident(_extension_context)
                    || ' ADD FUNCTION ' || _func_signature;
            end if;

            if _col_name like _pg_safer_settings_table.secret_setting_prefix || '%' then
                execute 'CREATE OR REPLACE FUNCTION ' || _func_signature
                        || ' RETURNS ' || _col_type
                        || ' LANGUAGE SQL'
                        || ' STABLE LEAKPROOF PARALLEL SAFE'
                        || ' RETURN (SELECT ' || quote_ident(_col_name)
                            || ' FROM ' || quote_ident(tg_table_schema) || '.' || quote_ident(tg_table_name)
                        || ')';
            else
                execute 'CREATE OR REPLACE FUNCTION ' || _func_signature
                        || ' RETURNS ' || _col_type
                        || ' LANGUAGE SQL'
                        || ' IMMUTABLE LEAKPROOF PARALLEL SAFE'
                        || ' RETURN ' || quote_nullable(_val_new) || '::' || _col_type;
            end if;

            if
                _extension_context is not null
                and _extension_context is distinct from _pg_safer_settings_table.owning_extension_name
            then
                -- The changing of this setting (and the (re)creating of the wrapper function) was triggered
                -- by an extension set up script, but _not_ the extension that owns the configuration table.
                -- The `CREATE OR REPLACE FUNCTION` will have made the (re)created function belong to the
                -- triggering extension.  Let it relinguish the function.
                execute 'ALTER EXTENSION ' || quote_ident(_extension_context)
                    || ' DROP FUNCTION ' || _func_signature;
                if _pg_safer_settings_table.owning_extension_name is not null then
                    -- The configuration table does belong to an extension.  Better give ownership of the
                    -- wrapper function back to that same extension.
                    execute 'ALTER EXTENSION ' || quote_ident(_pg_safer_settings_table.owning_extension_name)
                        || ' ADD FUNCTION ' || _func_signature;
                end if;
            end if;

            execute 'COMMENT ON FUNCTION ' || _func_signature
                        || $sqlstr$ IS
$md$This function was generated by the `$sqlstr$ || tg_name || $sqlstr$` trigger on the `$sqlstr$ || tg_table_schema || $sqlstr$.$sqlstr$ || tg_table_name || $sqlstr$` table.

This function wraps around the value of the `$sqlstr$ || tg_table_name ||
$sqlstr$.$sqlstr$ || _col_name || $sqlstr$` column and is automatically
recreated every time that the value of that column changes.
$sqlstr$ || case
    when col_description(tg_relid, _col_no) is not null
    then $sqlstr$
See [`$sqlstr$ || tg_table_name || $sqlstr$`](#table-$sqlstr$ || tg_table_name || $sqlstr$) for documentation on the underlying column.
$sqlstr$
    else ''
end || $sqlstr$
$md$                    $sqlstr$;
        end if;

        for
            _col_privilege
        in
            select
                column_privileges.*
            from
                information_schema.column_privileges
            where
                column_privileges.table_schema = tg_table_schema
                and column_privileges.table_name = tg_table_name
                and column_privileges.column_name = _col_name
                and column_privileges.privilege_type = 'SELECT'
        loop
            execute 'GRANT EXECUTE ON FUNCTION '
                || quote_ident(tg_table_schema) || '.' || quote_ident(_func_name) || '()'
                || ' TO ' || case
                    when _col_privilege.grantee = 'PUBLIC' then 'PUBLIC'
                    else quote_ident(_col_privilege.grantee)
                end
                || case when _col_privilege.is_grantable = 'YES' then ' WITH GRANT OPTION' else '' end;
        end loop;
    end loop;

    return NEW;
end;
$$;

comment on function pg_safer_settings_table__create_or_replace_getters() is
$md$This trigger function automatically `CREATE OR REPLACE`s, for each configuration column in the table that it is attached to: a function that returns the current value for that column.

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
$md$;

--------------------------------------------------------------------------------------------------------------

create function pg_safer_settings_table__update_on_copy()
    returns trigger
    set search_path from current
    language plpgsql
    as $$
declare
    _copying bool;
begin
    assert tg_when = 'BEFORE';
    assert tg_level = 'ROW';
    assert tg_op = 'INSERT';
    assert tg_relid in (select table_regclass from pg_safer_settings_table);

    -- When we are inside a `COPY` command, it is likely that we're restoring from a `pg_dump`.
    -- Otherwise, why would you want to bulk insert into a singleton table (with max. 1 row)?
    _copying := tg_op = 'INSERT' and exists (
        select from
            pg_stat_progress_copy
        where
            relid = tg_relid
            and command = 'COPY FROM'
            and type = 'PIPE'
    );

    if _copying then
        execute 'UPDATE ' || tg_relid::regclass::text || ' SET '
            || (
                select
                    string_agg(
                        quote_ident(pg_attribute.attname) || ' = $1.' || quote_ident(pg_attribute.attname)
                        ,', '
                    )
                from
                    pg_catalog.pg_attribute
                where
                    pg_attribute.attrelid = tg_relid
                    and pg_attribute.attnum > 0
            )
            using NEW;

        return null;  -- Cancel INSERT.
    end if;

    return NEW;
end;
$$;

comment on function pg_safer_settings_table__update_on_copy() is
$md$`UPDATE` instead of `INSERT` when triggered from a `COPY FROM STDIN` statement.

Without this trigger, when another extension sets up a
`pg_safer_settings_table` from one of its setup scripts, `pg_restore` will
crash, because it would try to `INSERT` _twice_:

1. as a result of the `INSERT AFTER` trigger on `pg_safer_settings_table`, _and_
2. as a result of the contents of the created settings table always being
   included in the `pg_dump`.  Because you want to remember your settings, right?
$md$;

--------------------------------------------------------------------------------------------------------------

create function pg_safer_settings_table__col_must_mirror_current_setting()
    returns trigger
    set search_path from current
    language plpgsql
    as $$
declare
    _cfg_column name;
    _pg_setting_name text;
    _db_setting_value text;
    _new_value_text text;
begin
    assert tg_when = 'BEFORE';
    assert tg_level = 'ROW';
    assert tg_op in ('INSERT', 'UPDATE');
    assert tg_table_schema = current_schema;
    assert tg_relid in (select table_regclass from pg_safer_settings_table);
    assert tg_nargs = 2;

    _cfg_column := tg_argv[0];
    _pg_setting_name := tg_argv[1];

    execute format('SELECT %s.%I::TEXT', '$1', _cfg_column) using NEW into _new_value_text;

    if current_setting(_pg_setting_name, true) is null then
        raise exception 'current_setting(''%'', true) IS NULL;'
            ' therefore the `%.%.%` column has to be `NULL` as well.',
            _pg_setting_name, tg_table_schema, tg_table_name, _cfg_column;
    end if;

    if current_setting(_pg_setting_name, true) != _new_value_text then
        raise exception 'current_setting(''%'', true) ≠ ''%'' = new `%.%.%` value.',
            _pg_setting_name, _new_value_text, tg_table_schema, tg_table_name, _cfg_column;
    end if;

    return true;
end;
$$;

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

--------------------------------------------------------------------------------------------------------------

create function pg_safer_settings_table__col_must_mirror_db_role_setting()
    returns trigger
    set search_path from current
    language plpgsql
    as $$
declare
    _cfg_column name;
    _pg_setting_name text;
    _regrole regrole;
    _db_setting_value text;
    _new_value_text text;
begin
    assert tg_when = 'AFTER';
    assert tg_level = 'ROW';
    assert tg_op in ('INSERT', 'UPDATE');
    assert tg_relid in (select table_regclass from pg_safer_settings_table);
    assert tg_nargs between 2 and 3;

    _cfg_column := tg_argv[0];
    _pg_setting_name := tg_argv[1];
    _regrole := null;
    if tg_nargs > 2 then
        _regrole := tg_argv[2];
    end if;

    execute format('SELECT %s.%I::TEXT', '$1', _cfg_column) using NEW into _new_value_text;

    _db_setting_value := app.pg_db_setting(_pg_setting_name, _regrole);

    if _db_setting_value is distinct from _new_value_text then
        raise exception 'New `%.%.%` value % is not in sync with DB(-role)-level setting ''%''.',
            tg_table_schema, tg_table_name, _cfg_column, _new_value_text, _pg_setting_name;
    end if;

    return NEW;
end;
$$;

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

--------------------------------------------------------------------------------------------------------------

create function pg_safer_settings_table__mirror_col_to_db_role_setting()
    returns trigger
    set search_path from current
    language plpgsql
    as $$
declare
    _cfg_column name;
    _pg_setting_name text;
    _regrole regrole;
    _db_setting_value text;
    _new_value_text text;
begin
    assert tg_when = 'AFTER';
    assert tg_level = 'ROW';
    assert tg_op in ('INSERT', 'UPDATE');
    assert tg_relid in (select table_regclass from pg_safer_settings_table);
    assert tg_nargs between 2 and 3;

    _cfg_column := tg_argv[0];
    _pg_setting_name := tg_argv[1];
    _regrole := null;
    if tg_nargs > 2 then
        _regrole := tg_argv[2];
    end if;

    execute format('SELECT %s.%I::TEXT', '$1', _cfg_column) using NEW into _new_value_text;

    _db_setting_value := app.pg_db_setting(_pg_setting_name, _regrole);

    if _db_setting_value is distinct from _new_value_text then
        if _regrole is null then
            execute 'ALTER DATABASE ' || current_database() || ' SET ' || _pg_setting_name
                || ' TO ' || quote_literal(_new_value_text);
        else
            execute 'ALTER ROLE ' || _regrole::text
                || ' IN DATABASE ' || current_database()
                || ' SET ' ||  _pg_setting_name || ' TO ' || quote_literal(_new_value_text);
        end if;
    end if;

    return NEW;
end;
$$;

comment on function pg_safer_settings_table__mirror_col_to_db_role_setting() is
$md$If, for some reason, you find it useful to keep a configuration column value synced to a database/role-level setting, this trigger function has your back.

For the opposite requirement—to enforce equality of a configuration column
value to a database (role) setting—, see the
`pg_safer_settings_table__col_must_mirror_db_role_setting()` trigger function.
$md$;

--------------------------------------------------------------------------------------------------------------

create procedure test__pg_safer_settings_table()
    set search_path from current
    set pg_readme.include_this_routine_definition to true
    language plpgsql
    as $$
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
$$;

--------------------------------------------------------------------------------------------------------------

create procedure test_dump_restore__pg_safer_settings_table(test_stage$ text)
    set search_path from current
    set plpgsql.check_asserts to true
    set pg_readme.include_this_routine_definition to true
    language plpgsql
    as $$
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
$$;

--------------------------------------------------------------------------------------------------------------
