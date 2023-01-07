-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION pg_safer_settings" to load this file. \quit

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

comment
    on function pg_safer_settings_version()
    is $markdown$
Returns the currently (being) installed version of the `pg_safer_settings` extension.
$markdown$;

--------------------------------------------------------------------------------------------------------------

alter table pg_safer_settings_table
    alter column pg_safer_settings_version
        set default pg_safer_settings_version();

--------------------------------------------------------------------------------------------------------------

do $$
begin
    if to_regprocedure('pg_installed_extension_version(name)') is not null then
        if exists (
            select
            from
                pg_catalog.pg_extension
            inner join
                pg_catalog.pg_depend
                on pg_depend.refobjid = pg_extension.oid
                and pg_depend.refclassid = 'pg_catalog.pg_extension'::regclass
            where
                pg_depend.classid = 'pg_catalog.pg_proc'::regclass
                and pg_depend.objid = 'pg_installed_extension_version(name)'::regprocedure
        ) or obj_description('pg_installed_extension_version(name)'::regprocedure, 'pg_proc')
            ~ 'This function belongs to the `pg_safer_settings` extension'
        then
            -- There might, due to my (Rowan's) short-sightedness, still be another extension that depends
            -- on the object, though not having this present extension as a dependency.  Therefore, we DROP
            -- it tentatively.
            drop function pg_installed_extension_version(name);
        end if;
    end if;
exception
    when dependent_objects_still_exist then
end;
$$;

--------------------------------------------------------------------------------------------------------------

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
        ,'gpl_3'
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

--------------------------------------------------------------------------------------------------------------

comment
    on function pg_safer_settings_meta_pgxn()
    is $markdown$
Returns the JSON meta data that has to go into the `META.json` file needed for
[PGXN—PostgreSQL Extension Network](https://pgxn.org/) packages.

The `Makefile` includes a recipe to allow the developer to: `make META.json` to
refresh the meta file with the function's current output, including the
`default_version`.

And indeed, `pg_safer_settings` can be found on PGXN:
https://pgxn.org/dist/pg_safer_settings/
$markdown$;

--------------------------------------------------------------------------------------------------------------

comment
    on extension pg_safer_settings
    is $markdown$
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

<?pg-readme-reference?>

<?pg-readme-colophon?>
$markdown$;

--------------------------------------------------------------------------------------------------------------
