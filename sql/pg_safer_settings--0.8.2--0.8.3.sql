-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION pg_safer_settings" to load this file. \quit


/**
 * CHANGELOG.md:
 *
 * - The `pg_safer_settings_table__create_or_replace_getters()` trigger function
 *   was fixed to not quote the `PUBLIC` keyword in the `GRANT … TO PUBLIC`
 *   command.
 */
create or replace function pg_safer_settings_table__create_or_replace_getters()
    returns trigger
    set search_path from current
    language plpgsql
    as $$
declare
    _func_name name;
    _col_name name;
    _col_type text;
    _col_no int;
    _val_old text;
    _val_new text;
    _pg_safer_settings_table pg_safer_settings_table;
    _col_privilege information_schema.column_privileges;
begin
    assert tg_when = 'AFTER';
    assert tg_level = 'ROW';
    assert tg_op in ('INSERT', 'UPDATE');
    assert tg_relid in (select table_regclass from pg_safer_settings_table);

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

        execute format('SELECT %s.%I::TEXT', '$1', _col_name) using NEW into _val_new;
        if tg_op = 'UPDATE' then
            execute format('SELECT %s.%I::TEXT', '$1', _col_name) using OLD into _val_old;
        else
            _val_old := null;
        end if;
        if _val_old is distinct from _val_new
            or to_regproc(quote_ident(tg_table_schema) || '.' || quote_ident(_func_name) || '()') is null
        then
            if _col_name like _pg_safer_settings_table.secret_setting_prefix || '%' then
                execute 'CREATE OR REPLACE FUNCTION '
                        || quote_ident(tg_table_schema) || '.' || quote_ident(_func_name) || '()'
                        || ' RETURNS ' || _col_type
                        || ' LANGUAGE SQL'
                        || ' STABLE LEAKPROOF PARALLEL SAFE'
                        || ' RETURN (SELECT ' || quote_ident(_col_name)
                            || ' FROM ' || quote_ident(tg_table_schema) || '.' || quote_ident(tg_table_name)
                        || ')';
            else
                execute 'CREATE OR REPLACE FUNCTION '
                        || quote_ident(tg_table_schema) || '.' || quote_ident(_func_name) || '()'
                        || ' RETURNS ' || _col_type
                        || ' LANGUAGE SQL'
                        || ' IMMUTABLE LEAKPROOF PARALLEL SAFE'
                        || ' RETURN ' || quote_nullable(_val_new) || '::' || _col_type;
            end if;

            execute 'COMMENT ON FUNCTION '
                        || quote_ident(tg_table_schema) || '.' || quote_ident(_func_name) || '()'
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
