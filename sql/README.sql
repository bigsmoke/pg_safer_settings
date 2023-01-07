\pset tuples_only
\pset format unaligned

begin;

create schema ext;

create extension pg_safer_settings
    with schema ext
    cascade;

select ext.pg_safer_settings_readme();

rollback;
