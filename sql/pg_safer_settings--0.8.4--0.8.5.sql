-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION pg_safer_settings" to load this file. \quit


/**
 * CHANGELOG.md:
 *
 * - Accommodations were made to allow third-party extensions to keep their
 *   settings in a `pg_safer_settings`-managed table, and thusly registed in the
 *   `pg_safer_settings_table` registery:
 *
 *   + Two new columns were added to the `pg_safer_settings_table` registery
 *     table:
 *
 *     1. `owning_extension_name`, and
 *     2. `owning_extension_version`.
 */
alter table pg_safer_settings_table
    add column owning_extension_name name
    ,add column owning_extension_version text
;

comment on column pg_safer_settings_table.owning_extension_name is
$md$The name of the extension that registered a specific settings table.

Make sure that this column contains the name of your extension if your
extension inserts a `pg_safer_settings_table` through its set up scripts.
$md$;

comment on column pg_safer_settings_table.owning_extension_version is
$md$The version of the extension that registered a specific settings table.

This version is set automatically by the `pg_safer_settings_table__register()`
trigger function.
$md$;


/**
 * CHANGELOG.md:
 *
 *   + All rows in the `pg_safer_settings_table` `WHERE owning_extension_name
 *     IS NOT NULL` are now excluded from the dump, so that when dependent
 *     extensions reregister/recreate their config tables during `CREATE
 *     EXTENSION` during a `pg_restore`, that third-party extension's
 *     installation/upgrade do not encounter the problem of the row already
 *     existing.
 */
select pg_catalog.pg_extension_config_dump(
    'pg_safer_settings_table'
    ,'WHERE owning_extension_name IS NULL'
);


/**
 * CHANGELOG.md:
 *
 *   + The `test_dump_restore__pg_safer_settings_table()` procedure was taught
 *     to test what happens when working with a subextension that also adds a
 *     configuration table registered with the `pg_safer_settings_table`.
 */
create or replace procedure test_dump_restore__pg_safer_settings_table(test_stage$ text)
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
        assert current_subext_text_setting() = 'quite the thing';
    end if;
end;
$$;


/**
 * CHANGELOG.md:
 *
 *   + `pg_safer_settings_table__update_on_copy()` is a new trigger function,
 *     which serves to let `pg_safer_settings`-managed config tables be updated
 *     instead of `INSERT/*ed*/ INTO` on `COPY FROM`—that is, while a config
 *     table is being `pg_restore`d from a `pg_dump`.
 *     ~
 *     Note that there is no need (or use) for the upgrade script to add this
 *     trigger to already existing config tables, because the triggers are
 *     recreated anyway when the extension is restored during `pg_restore`.
 */
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

Without this trigger, when another extension sets up a `pg_safer_settings_table` from one of its setup scripts
$md$;


/**
 * CHANGELOG.md:
 *
 *   + The `pg_safer_settings_table__register()` trigger function was updated to
 *     set up an `update_on_copy` trigger using the aforementioned trigger
 *     function on newly-registered `pg_safer_settings`-managed config tables.
 *
 *   + (The code documentation in the `pg_safer_settings_table__register()`
 *     function is improved, as is the comments on the `no_delete` trigger
 *     created _by_ that function.)
 *
 *   + When another extension registers its own `pg_safer_settings`-managed
 *     configuration table (and telling so to the registery in
 *     `pg_safer_settings_table` by specifying its `owning_extension_name`,
 *     the `pg_safer_settings_table__register()` trigger function will now
 *     make sure that the contents of the newly registered table are
 *     included by `pg_dump`.
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


/**
 * CHANGELOG.md:
 *
 * - A faulty comparison was fixed in the `pg_safer_settings_table_columns()`
 *   function; `column_name != any` was was supposed to be `not column_name =
 *   any`.
 */
create or replace function pg_safer_settings_table_columns(table_schema$ name, table_name$ name)
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
