-- Complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION pg_safer_settings" to load this file. \quit


/**
 * CHANGELOG.md:
 *
 * - An _Authors and contributors_ section was added to the `COMMENT ON
 *   EXTENSION` from which the `README.md` is generated (using the
 *   `pg_safer_settings_readme()` function, powerd by the `pg_readme`
 *   extension).
 */
comment on extension pg_safer_settings is $markdown$
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

## Authors and contributors

* [Rowan](https://www.bigsmoke.us/) originated this extension in 2022 while
  developing the PostgreSQL backend for the [FlashMQ SaaS MQTT cloud
  broker](https://www.flashmq.com/).  Rowan does not like to see himself as a
  tech person or a tech writer, but, much to his chagrin, [he
  _is_](https://blog.bigsmoke.us/category/technology). Some of his chagrin
  about his disdain for the IT industry he poured into a book: [_Why
  Programming Still Sucks_](https://www.whyprogrammingstillsucks.com/).  Much
  more than a “tech bro”, he identifies as a garden gnome, fairy and ork rolled
  into one, and his passion is really to [regreen and reenchant his
  environment](https://sapienshabitat.com/).  One of his proudest achievements
  is to be the third generation ecological gardener to grow the wild garden
  around his beautiful [family holiday home in the forest of Norg, Drenthe,
  the Netherlands](https://www.schuilplaats-norg.nl/) (available for rent!).

<?pg-readme-reference?>

<?pg-readme-colophon?>
$markdown$;
