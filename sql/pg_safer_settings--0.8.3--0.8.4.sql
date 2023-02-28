-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION pg_safer_settings" to load this file. \quit

--------------------------------------------------------------------------------------------------------------

-- Put the synopsis on the first line, as a single line, to please PostgREST's
-- parsing for its OpenAPI docs.
comment on function pg_db_setting(text, regrole) is
$markdown$`pg_db_setting()` allows you to look up a setting value as `SET` for a `DATABASE` or `ROLE`, ignoring the local (transaction or session) value for that setting.

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
$markdown$;

--------------------------------------------------------------------------------------------------------------
