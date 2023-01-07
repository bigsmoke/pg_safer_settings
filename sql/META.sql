\pset tuples_only
\pset format unaligned

begin;

create extension pg_safer_settings
    cascade;

select jsonb_pretty(pg_safer_settings_meta_pgxn());

rollback;
