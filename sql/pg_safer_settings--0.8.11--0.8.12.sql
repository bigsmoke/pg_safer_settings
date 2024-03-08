-- Complain if script is sourced in `psql`, rather than via `CREATE EXTENSION`.
\echo Use "CREATE EXTENSION pg_safer_settings" to load this file. \quit

--------------------------------------------------------------------------------------------------------------

-- Ignore generated columns.
create or replace function pg_safer_settings_table__update_on_copy()
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
                    and pg_attribute.attgenerated = ''
            )
            using NEW;

        return null;  -- Cancel INSERT.
    end if;

    return NEW;
end;
$$;

--------------------------------------------------------------------------------------------------------------

-- Test that generated columns are ignored on `UPDATE` on `COPY`.
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
            ,add generated_setting text
                not null
                generated always as (case when boolean_test_setting then 'yes' else 'no' end) stored
            ,add secret_test_setting text
        ;
        update test__cfg
            set secret_test_setting = 'Th1s1ss3cr3t'
        ;

        create extension pg_safer_settings_table_dependent_extension;
        assert current_subext_number_setting() = 4;
        assert current_subext_bool_setting();
        assert current_subext_generated_setting() = 'yes';
        update subextension_cfg set subext_number_setting = 5;
        assert current_subext_number_setting() = 5;

        create extension pg_safer_settings_table_dependent_subextension;
        assert current_subext_text_setting() = 'Set by subsubextension';

    elsif test_stage$ = 'post-restore' then
        select * into strict _cfg_record from test__cfg;

        assert _cfg_record.boolean_test_setting = false;
        assert current_boolean_test_setting() = false;
        assert _cfg_record.generated_setting = 'no';
        assert current_generated_setting() = 'no';

        assert _cfg_record.secret_test_setting = 'Th1s1ss3cr3t';
        assert current_secret_test_setting() = 'Th1s1ss3cr3t';

        assert to_regprocedure('current_boolean_test_setting()') is not null;
        assert to_regprocedure('current_generated_setting()') is not null;
        assert to_regprocedure('current_secret_test_setting()') is not null;

        delete from pg_safer_settings_table where table_name = 'test__cfg';

        assert to_regprocedure('current_boolean_test_setting()') is null;
        assert to_regprocedure('current_generated_setting()') is null;
        assert to_regprocedure('current_secret_test_setting()') is null;

        assert current_subext_number_setting() = 5,
            'The configaration value set _after_ `CREATE EXTENSION` should have been preserved.';
        assert current_subext_bool_setting() = true;
        assert current_subext_generated_setting() = 'yes';

        assert current_subext_text_setting() = 'Set by subsubextension',
            'The configuration value set by the subsubextension should have been preserver.';
    end if;
end;
$$;

--------------------------------------------------------------------------------------------------------------
