# `pg_safer_settings` changelog / release notes

All notable changes to the `pg_safer_settings` PostgreSQL extension are
documented in this changelog.

The format of this changelog is based on [Keep a
Changelog](https://keepachangelog.com/en/1.1.0/).
`pg_safer_settings` adheres to [semantic
versioning](https://semver.org/spec/v2.0.0.html).

This changelog is **automatically generated** and is updated by running `make
CHANGELOG.md`.  This preamble is kept in `CHANGELOG.preamble.md` and the
remainder of the changelog below is synthesized (by `sql-to-changelog.md.sql`)
from special comments in the extension update scripts, put in the right sequence
with the help of the `pg_extension_update_paths()` functions (meaning that the
extension update script must be installed where Postgres can find them before an
up-to-date `CHANGELOG.md` file can be generated).

---

## [1.0.0] – unreleased

[1.0.0]: https://github.com/bigsmoke/pg_safer_settings/compare/v0.8.12…v1.0.0

- 1.0.0 marks the first “stable” release of `pg_safer_settings`, as per the
  definitions and commitments that this entails, as per the [_SemVer 2.0.0
  Spec_](https://semver.org/spec/v2.0.0.html):

  > 4. Major version zero (0.y.z) is for initial development. Anything MAY
  >    change at any time. The public API SHOULD NOT be considered stable.
  > 5. Version 1.0.0 defines the public API. The way in which the version
  >    number is incremented after this release is dependent on this public
  >    API and how it changes.

- A `CHANGELOG.md` was created, generated from a concatenation of special
  comments that were added to all existing extension upgrade scripts.
  Henceforth, such comments will be maintained in all new extension upgrade
  scripts as well, as to simultaneously keep the `CHANGELOG.md` up-to-date
  and have the upgrade scripts be more self-documenting.

- `make` now respects `EXTENSION_ENTRY_VERSIONS` if it was already supplied
  from the environment.

- For the 1.0 release, the braindead, needless dependency of
  `pg_safer_settings` on `pg_utility_trigger_functions` was gotten rid of.
  The only function from `pg_utility_trigger_functions` that was used
  was `no_delete()`—a function so simple that Rowan found it difficult to
  believe that his past self imported that as a dependency rather then
  simply copy-pasting it.
  ~
  Well, `pg_safer_settings_table__no_delete()` now replaces `no_delete()`
  and, as a consequence, this new function also gives clearer error
  messages which are better suited to `pg_safer_settings`.
  The `comment on pg_safer_settings_table__no_delete()` is also much more
  informative, with it being contextualized to the `pg_safer_settings`
  extensions rather that being a generic explanation of `no_delete()` its
  function.

  + The `comment on pg_safer_settings_table__no_delete()` is also much more
    informative, with it being contextualized to the `pg_safer_settings`
    extensions rather that being a generic explanation of `no_delete()` its
    function.

  + `pg_safer_settings_table__register()` uses the new trigger function.

  + Existing `no_delete` `BEFORE` triggers on config tables are recreated to
    use the new `pg_safer_settings_table__no_delete()` function when
    upgrading from `pg_safer_settings` version 0.8.12 to 1.0.0.

  + Of course, `pg_utility_trigger_functions` is now also removed from the
    runtime requirements in `META.json`.

- The new `pg_db_role_setting(oid, regrole, jsonb)` constructor function
  make it trivial to contruct a `pg_catalog.pg_db_role_setting` row from
  a `jsonb` object:
  ~
  ```
  pg_db_role_setting(_db_oid, current_user, '{"ext.var_1": "one", "ext.var_2", "two"}'::jsonb);
  ```

  + The `test__pg_db_role_setting()` procedure provides executable example of
    this function's use.

## [0.8.12] – 2024-03-08

[0.8.12]: https://github.com/bigsmoke/pg_safer_settings/compare/v0.8.11…v0.8.12

- The `pg_safer_settings_table__update_on_copy()` trigger function now
  ignores configuration columns that are `GENERATED ALWAYS AS (…) STORED`,
  so that it doesn't accidentelly `UPDATE` columns which would produce
  an error.

- Accordingly, the `test_dump_restore__pg_safer_settings_table()` procedure
  now includes a `generated_setting` in its test configuration table.

## [0.8.11] – 2023-11-28

[0.8.11]: https://github.com/bigsmoke/pg_safer_settings/compare/v0.8.10…v0.8.11

- When the `PG_CONFIG` environment variable is already set when running
  `make`, the `Makefile` now uses that value instead of setting it itself.

## [0.8.10] – 2023-06-19

[0.8.10]: https://github.com/bigsmoke/pg_safer_settings/compare/v0.8.9…v0.8.10

- The technical characteristics and design choices of the behavior of the
  `pg_safer_settings_table` table are now extensively documented.

## [0.8.9] – 2023-05-13

[0.8.9]: https://github.com/bigsmoke/pg_safer_settings/compare/v0.8.8…v0.8.9

- An _Authors and contributors_ section was added to the `COMMENT ON
  EXTENSION` from which the `README.md` is generated (using the
  `pg_safer_settings_readme()` function, powerd by the `pg_readme`
  extension).

## [0.8.8] – 2023-05-01

[0.8.8]: https://github.com/bigsmoke/pg_safer_settings/compare/v0.8.7…v0.8.8

- A `CHECK` constraint was added to `pg_safer_settings_table` to enforce
  that either the `owning_extension_name` and `owning_extension_version`
  columns are both null or neither of them are null.

- The `pg_safer_settings_readme()` function now installs the `pg_readme`
  extension `WITH CASCADE`, in case that its `hstore` dependency is also
  not already installed while the function is running.

- Some `COMMENT`s were improved and cleaned up, so that:

  + the first (synopsis) paragraph is always on one line,
  + which is also the first line of the `comment`, and
  + there are no links on that line;

  This concerned the `COMMENT`s:

  1. `on function pg_safer_settings_readme()`;

  2. `on function pg_safer_settings_meta_pgxn()`, which also had some
     punctuation fixed;

  3. `on table pg_safer_settings_table`;

  4. `on column pg_safer_settings_table.secret_setting_prefix`;

  5. `on function pg_safer_settings_table__col_must_mirror_current_setting()`; and

  6. `on function pg_safer_settings_table__col_must_mirror_db_role_setting()`;

## [0.8.7] – 2023-04-12

[0.8.7]: https://github.com/bigsmoke/pg_safer_settings/compare/v0.8.6…v0.8.7

- The `README.md` was not rebuilt during the previous release.  This is now
  remedied.

## [0.8.6] – 2023-04-12

[0.8.6]: https://github.com/bigsmoke/pg_safer_settings/compare/v0.8.5…v0.8.6

- The `comment on function pg_safer_settings_table__update_on_copy()` was
  left unfinished mid-sentence in the `pg_safer_settings----0.8.4--0.8.5.sql`
  upgrade script.  This is now remedied.

- The `test_dump_restore__pg_safer_settings_table()` procedure now tests what
  happens when an extension's configuration table is touched by another
  extension.

- The `pg_safer_settings_table__create_or_replace_getters()` trigger function
  can now deal well with multiple levels of dependent extensions.  I.e., if,
  for example, extension B changes a setting that belongs to extension A,
  extension B will no longer accidentally end up as the owner of the newly
  created getter function.

- The `pg_safer_settings_table__create_or_replace_getters()` trigger function
  was somewhat DRY'd in the process.

## [0.8.5] – 2023-03-15

[0.8.5]: https://github.com/bigsmoke/pg_safer_settings/compare/v0.8.4…v0.8.5

- Accommodations were made to allow third-party extensions to keep their
  settings in a `pg_safer_settings`-managed table, and thusly registed in the
  `pg_safer_settings_table` registery:

  + Two new columns were added to the `pg_safer_settings_table` registery
    table:

    1. `owning_extension_name`, and
    2. `owning_extension_version`.

  + All rows in the `pg_safer_settings_table` `WHERE owning_extension_name
    IS NOT NULL` are now excluded from the dump, so that when dependent
    extensions reregister/recreate their config tables during `CREATE
    EXTENSION` during a `pg_restore`, that third-party extension's
    installation/upgrade do not encounter the problem of the row already
    existing.

  + The `test_dump_restore__pg_safer_settings_table()` procedure was taught
    to test what happens when working with a subextension that also adds a
    configuration table registered with the `pg_safer_settings_table`.

  + `pg_safer_settings_table__update_on_copy()` is a new trigger function,
    which serves to let `pg_safer_settings`-managed config tables be updated
    instead of `INSERT/*ed*/ INTO` on `COPY FROM`—that is, while a config
    table is being `pg_restore`d from a `pg_dump`.
    ~
    Note that there is no need (or use) for the upgrade script to add this
    trigger to already existing config tables, because the triggers are
    recreated anyway when the extension is restored during `pg_restore`.

  + The `pg_safer_settings_table__register()` trigger function was updated to
    set up an `update_on_copy` trigger using the aforementioned trigger
    function on newly-registered `pg_safer_settings`-managed config tables.

  + (The code documentation in the `pg_safer_settings_table__register()`
    function is improved, as is the comments on the `no_delete` trigger
    created _by_ that function.)

  + When another extension registers its own `pg_safer_settings`-managed
    configuration table (and telling so to the registery in
    `pg_safer_settings_table` by specifying its `owning_extension_name`,
    the `pg_safer_settings_table__register()` trigger function will now
    make sure that the contents of the newly registered table are
    included by `pg_dump`.

- A faulty comparison was fixed in the `pg_safer_settings_table_columns()`
  function; `column_name != any` was was supposed to be `not column_name =
  any`.

## [0.8.4] – 2023-02-28

[0.8.4]: https://github.com/bigsmoke/pg_safer_settings/compare/v0.8.3…v0.8.4

- The `comment on function pg_db_setting(text, regrole)` was changed to put
  the entire synopsis paragraph, as a single line, on the first line of the
  `comment`, to please PostgREST's parsing for its OpenAPI docs.

## [0.8.3] – 2023-02-28

[0.8.3]: https://github.com/bigsmoke/pg_safer_settings/compare/v0.8.2…v0.8.3

- The `pg_safer_settings_table__create_or_replace_getters()` trigger function
  was fixed to not quote the `PUBLIC` keyword in the `GRANT … TO PUBLIC`
  command.

## [0.8.2] – 2023-02-24

[0.8.2]: https://github.com/bigsmoke/pg_safer_settings/compare/v0.8.1…v0.8.2

- The `pg_dump`-ing and `pg_restore`-ing of settings managed by
  `pg_safer_settings` is now also tested automatically, by the
  `test_dump_restore__pg_safer_settings_table()` procedure.

- The new `test_dump_restore__pg_safer_settings_table()` procedure did
  indeed expose a bug in `pg_safer_settings` while restoring: the
  `pg_safer_settings_table__register()` function crashed when a
  `pg_safer_settings`-managed config table already existed, even in the
  context of a `COPY` command.

  + `pg_safer_settings_table__register()` now no longer minds if the
    registered table already exists, as long as the trigger is executed
    in the context of a `COPY` command.

  + Additionally, error messages that are raised when trying to `INSERT`
    (not `COPY`) a row for a table that _does_ already exist have been
    improved.

  + And a `comment on function pg_safer_settings_table__register()` makes it
    so that the trigger function now also has a description in the
    `README.md`.

## [0.8.1] – 2023-02-23

[0.8.1]: https://github.com/bigsmoke/pg_safer_settings/compare/v0.8.0…v0.8.1

- `comment on function pg_safer_settings_table__mirror_col_to_db_role_setting()`
  was changed to have the first paragraph on a single line, to play nicer
  with everything that is _not_ `pg_readme`.

## [0.8.0] – 2023-02-04

[0.8.0]: https://github.com/bigsmoke/pg_safer_settings/compare/v0.7.0…v0.8.0

- Getter functions that are automatically created by the
  `pg_safer_settings_table__create_or_replace_getters()` trigger function now
  get an explanatory `COMMENT`.

- `comment on function pg_safer_settings_table__create_or_replace_getters()`
  was changed to have the first paragraph on a single line, to play nicer
  with everything that is _not_ `pg_readme`.  Besides, the comment now also
  better explains what the trigger function does.

## [0.7.0] – 2023-02-04

[0.7.0]: https://github.com/bigsmoke/pg_safer_settings/compare/v0.6.1…v0.7.0

- The license of `pg_safer_settings` was changed from AGPL 3.0 to the
  PostgreSQL license.

## [0.6.1] – 2023-01-07

[0.6.1]: https://github.com/bigsmoke/pg_safer_settings/compare/v0.6.0…v0.6.1

- The new `pg_safer_settings_version()` function returns the currently
  (being) installed version of the `pg_safer_settings` extension.

- The `pg_safer_settings_version` column of the `pg_safer_settings_table`
  registry table was altered to use this new `pg_safer_settings_version()`
  function for its default expression instead of the too generic
  `pg_installed_extension_version(name)` function which was misguidedly part
  of more than one of Rowan's PostgreSQL extensions.

- If the generic `pg_installed_extension_version(name)` function was
  installed _and_ owned by the `pg_safer_settings` extension, that function
  will be dropped when you upgrade from `pg_safer_settings` 0.6.0 to
  `pg_safer_settings` 0.6.1.

- The `pg_safer_settings` project is now PGXN compatible.  The `META.json`
  file is generated using the new `pg_safer_settings_meta_pgxn()` funciton.

- An _Origin_ section was added to the `README.md`, to credit the FlashMQ
  project as the soil from whence which this project grew.

- The `README.md` was regenerated using the newest version of the
  [`pg_readme`](https://github.com/bigsmoke/pg_readme) extension.
