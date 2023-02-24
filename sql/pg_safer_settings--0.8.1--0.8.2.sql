-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION pg_safer_settings" to load this file. \quit

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
    end if;
end;
$$;

--------------------------------------------------------------------------------------------------------------

-- Don't mind pre-existing config-table if trigger function is executed in the context of a COPY command.
-- Improve error messages when trying to INSERT (not COPY) a row for a table that _does_ already exist.
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
    -- Otherwise, why would you want to bulk insert into a singleton table (with max. 1 row)?
    _copying := tg_op = 'INSERT' and exists (
        select from
            pg_stat_progress_copy
        where
            relid = tg_relid
            and command = 'COPY FROM'
            and type = 'PIPE'
    );

    if tg_op = 'INSERT' and tg_when = 'BEFORE' and _copying then
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

        execute 'CREATE TRIGGER create_or_replace_getters'
            || ' AFTER INSERT OR UPDATE ON ' || NEW.table_regclass::text
            || ' FOR EACH ROW'
            || ' EXECUTE FUNCTION pg_safer_settings_table__create_or_replace_getters()';

        execute 'CREATE TRIGGER no_delete'
            || ' BEFORE DELETE ON ' || NEW.table_regclass::text
            || ' FOR EACH STATEMENT'
            || ' EXECUTE FUNCTION no_delete()';

        execute 'COMMENT ON TRIGGER no_delete ON ' || NEW.table_regclass::text
            || ' IS $markdown$
The `no_delete()` trigger function comes from the very unpretentious
[`pg_utility_trigger_functions`](https://github.com/bigsmoke/pg_utility_trigger_functions)
extension.
$markdown$';

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

--------------------------------------------------------------------------------------------------------------
