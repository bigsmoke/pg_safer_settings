-- Complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION pg_safer_settings" to load this file. \quit

--------------------------------------------------------------------------------------------------------------

-- This comment was unfinished mid-sentence in the `*--0.8.4--0.8.5.sql` script.
comment on function pg_safer_settings_table__update_on_copy() is
$md$`UPDATE` instead of `INSERT` when triggered from a `COPY FROM STDIN` statement.

Without this trigger, when another extension sets up a
`pg_safer_settings_table` from one of its setup scripts, `pg_restore` will
crash, because it would try to `INSERT` _twice_:

1. as a result of the `INSERT AFTER` trigger on `pg_safer_settings_table`, _and_
2. as a result of the contents of the created settings table always being
   included in the `pg_dump`. Because you want to remember your settings, right?
$md$;

--------------------------------------------------------------------------------------------------------------

-- Test what happens when an extension's configuration table is touched by another extension.
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

-- DRY.
-- Deal well with compatible with multiple levels of dependent extensions.
create or replace function pg_safer_settings_table__create_or_replace_getters()
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

            if _extension_context is not null
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

--------------------------------------------------------------------------------------------------------------
