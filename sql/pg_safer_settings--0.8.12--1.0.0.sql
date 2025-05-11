-- Complain if script is sourced in `psql`, rather than via `CREATE EXTENSION`.
\echo Use "CREATE EXTENSION pg_safer_settings" to load this file. \quit


/**
 * CHANGELOG.md:
 *
 * - 1.0.0 marks the first “stable” release of `pg_safer_settings`, as per the
 *   definitions and commitments that this entails, as per the [_SemVer 2.0.0
 *   Spec_](https://semver.org/spec/v2.0.0.html):
 *
 *   > 4. Major version zero (0.y.z) is for initial development. Anything MAY
 *   >    change at any time. The public API SHOULD NOT be considered stable.
 *   > 5. Version 1.0.0 defines the public API. The way in which the version
 *   >    number is incremented after this release is dependent on this public
 *   >    API and how it changes.
 *
 * - A `CHANGELOG.md` was created, generated from a concatenation of special
 *   comments that were added to all existing extension upgrade scripts.
 *   Henceforth, such comments will be maintained in all new extension upgrade
 *   scripts as well, as to simultaneously keep the `CHANGELOG.md` up-to-date
 *   and have the upgrade scripts be more self-documenting.
 *
 * - `make` now respects `EXTENSION_ENTRY_VERSIONS` if it was already supplied
 *   from the environment.
 */


/**
 * CHANGELOG.md:
 *
 * - For the 1.0 release, the braindead, needless dependency of
 *   `pg_safer_settings` on `pg_utility_trigger_functions` was gotten rid of.
 *   The only function from `pg_utility_trigger_functions` that was used
 *   was `no_delete()`—a function so simple that Rowan found it difficult to
 *   believe that his past self imported that as a dependency rather then
 *   simply copy-pasting it.
 *   ~
 *   Well, `pg_safer_settings_table__no_delete()` now replaces `no_delete()`
 *   and, as a consequence, this new function also gives clearer error
 *   messages which are better suited to `pg_safer_settings`.
 *   The `comment on pg_safer_settings_table__no_delete()` is also much more
 *   informative, with it being contextualized to the `pg_safer_settings`
 *   extensions rather that being a generic explanation of `no_delete()` its
 *   function.
 */
create function pg_safer_settings_table__no_delete()
    returns trigger
    set search_path from current
    language plpgsql
as $$
begin
    assert tg_when = 'AFTER';
    assert tg_level = 'ROW';
    assert tg_op = 'DELETE';
    assert tg_relid in (select table_regclass from pg_safer_settings_table);

    raise sqlstate 'P0DEL' using
        message = format(
            '`DELETE FROM %I.%I` not allowed; this table must alwasy contain a single(ton) row.'
            , tg_table_schema, tg_table_name
        )
        ,detail = format(
            'This `%I` trigger on `%I.%I` was created by the `pg_safer_settings_table__register()` function.'
            ,tg_name, tg_table_schema, tg_table_name
        )
    ;
end;
$$;

/**
 * CHANGELOG.md:
 *
 *   + The `comment on pg_safer_settings_table__no_delete()` is also much more
 *     informative, with it being contextualized to the `pg_safer_settings`
 *     extensions rather that being a generic explanation of `no_delete()` its
 *     function.
 */
comment on function pg_safer_settings_table__no_delete() is
$md$This trigger function is attached to each configuration table managed through the `pg_safer_settings_table` registry to altogether forbid `DELETE`ion of the singleton in these tables.

`pg_safer_settings`-managed configuration tables should always contain a single
row, which is why `DELETE` is blocked for every such table created via
[`pg_safer_settings_table`] registry and its main trigger function:
[`pg_safer_settings_table__register()`]

[`pg_safer_settings_table`]:
    #table-pg_safer_settings_table

[`pg_safer_settings_table__register()`]:
    #function-pg_safer_settings_table__register
$md$;


/**
 * CHANGELOG.md:
 *
 *   + `pg_safer_settings_table__register()` uses the new trigger function.
 */
create or replace function pg_safer_settings_table__register()
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
            || ' EXECUTE FUNCTION pg_safer_settings_table__no_delete()';

        execute 'COMMENT ON TRIGGER no_delete ON ' || NEW.table_regclass::text
            || ' IS ''This trigger is maintained by the `pg_safer_settings_table__register()` function.''';

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


/**
 * CHANGELOG.md:
 *
 *   + Existing `no_delete` `BEFORE` triggers on config tables are recreated to
 *     use the new `pg_safer_settings_table__no_delete()` function when
 *     upgrading from `pg_safer_settings` version 0.8.12 to 1.0.0.
 */
do $$
declare
    _table_regclass regclass;
begin
    for _table_regclass in
        select
            t.table_regclass
        from
            pg_safer_settings_table as t
        inner join
            pg_catalog.pg_trigger
            on pg_trigger.tgrelid = t.table_regclass
        inner join
            pg_catalog.pg_proc
            on pg_proc.oid = pg_trigger.tgfoid
        where
            pg_trigger.tgname = 'no_delete'
            and pg_proc.proname = 'no_delete'  -- The function from `pg_utility_trigger_functions`.
    loop
        raise notice using message = format(
        );
        execute format(
            'CREATE OR REPLACE TRIGGER no_delete BEFORE DELETE ON %I FOR EACH STATEMENT'
            ' EXECUTE FUNCTION pg_safer_settings_table__no_delete()'
            ,_table_regclass::text
        );
        execute 'COMMENT ON TRIGGER no_delete ON ' || _table_regclass::text
            || ' IS ''This trigger is maintained by the `pg_safer_settings_table__register()` function.''';
    end loop;
end;
$$;


/**
 * CHANGELOG.md:
 *
 *   + Of course, `pg_utility_trigger_functions` is now also removed from the
 *     runtime requirements in `META.json`.
 */
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
        ,'postgresql'
        ,'prereqs'
        ,'{
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
                "file": "pg_safer_settings--1.0.0.sql",
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


/**
 * CHANGELOG.md:
 *
 * - The new `pg_db_role_setting(oid, regrole, jsonb)` constructor function
 *   make it trivial to contruct a `pg_catalog.pg_db_role_setting` row from
 *   a `jsonb` object:
 *   ~
 *   ```
 *   pg_db_role_setting(_db_oid, current_user, '{"ext.var_1": "one", "ext.var_2", "two"}'::jsonb);
 *   ```
 */
create function pg_db_role_setting("db$" oid, "role$" regrole, "vars$" jsonb)
    returns pg_catalog.pg_db_role_setting
    stable
    leakproof
    parallel safe
    return row(
        $1
        ,$2
        ,(select array_agg("key" || '=' || "value") from jsonb_each_text($3))
    )::pg_catalog.pg_db_role_setting;

comment on function pg_db_role_setting(oid, regrole, jsonb) is
$md$Construct `pg_db_role_setting` row type, to avoid awkwardly contructing array of key-value strings.

See the [`test__pg_db_role_setting()`](#procedure-test__pg_db_role_setting)
procedure for example usage of the `pg_db_role_setting()` constructor.
$md$;


/**
 * CHANGELOG.md:
 *
 *   + The `test__pg_db_role_setting()` procedure provides executable example of
 *     this function's use.
 */
create procedure test__pg_db_role_setting()
    set search_path from current
    set plpgsql.check_asserts to true
    set pg_readme.include_this_routine_definition to true
    language plpgsql
    as $$
declare
    _db_oid oid := (select oid from pg_database where datname = current_database());
begin
    assert pg_db_role_setting(_db_oid, current_user::regrole, '{"ext.var_1": "one", "ext.var_2": "two"}'::jsonb) = row(
        _db_oid, current_user::regrole, '{ext.var_1=one,ext.var_2=two}'::text
    )::pg_db_role_setting;
end;
$$;

comment on procedure test__pg_db_setting() is
$md$Test and demonstrate `pg_db_role_setting()` constructor function.
$md$;
