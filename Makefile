reverse = $(if $(wordlist 2,2,$(1)),$(call reverse,$(wordlist 2,$(words $(1)),$(1))) $(firstword $(1)),$(1))

EXTENSION = pg_safer_settings

SUBEXTENSION = pg_safer_settings_table_dependent_extension
SUBSUBEXTENSION = pg_safer_settings_table_dependent_subextension

DISTVERSION = $(shell sed -n -E "/default_version/ s/^.*'(.*)'.*$$/\1/p" $(EXTENSION).control)

# Anchoring the changelog:
OLDEST_VERSION = 0.6.0

DATA = $(wildcard sql/$(EXTENSION)--*.sql)

UPDATE_SCRIPTS = $(wildcard sql/$(EXTENSION)--[0-99].[0-99].[0-99]--[0-99].[0-99].[0-99].sql)

REGRESS = test_extension_update_paths

PG_CONFIG ?= pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

install: install_subextension
install_subextension:
	$(MAKE) -C $(SUBEXTENSION) install

install: install_subsubextension
install_subsubextension:
	$(MAKE) -C $(SUBSUBEXTENSION) install

# Set some environment variables for the regression tests that will be fed to `pg_regress`:
installcheck: export EXTENSION_NAME=$(EXTENSION)
installcheck: export EXTENSION_ENTRY_VERSIONS?=$(patsubst sql/$(EXTENSION)--%.sql,%,$(wildcard sql/$(EXTENSION)--[0-99].[0-99].[0-99].sql))

README.md: sql/README.sql install
	psql --quiet postgres < $< > $@

META.json: sql/META.sql install
	psql --quiet postgres < $< > $@

CHANGELOG.md: bin/sql-to-changelog.md.sh sql/pg_extension_update_scripts_sequence.sql CHANGELOG.preamble.md install $(UPDATE_SCRIPTS)
	cat CHANGELOG.preamble.md > $@
	bin/sql-to-changelog.md.sh -r '## [%v] – %d' -u '## [%v] – unreleased' -c 'https://github.com/bigsmoke/pg_safer_settings/compare/%f…%t' -p $(call reverse,$(shell env EXTENSION_NAME=$(EXTENSION) EXTENSION_OLDEST_VERSION=$(OLDEST_VERSION) psql -X postgres < sql/pg_extension_update_scripts_sequence.sql)) >> $@

dist: META.json README.md
	git archive --format zip --prefix=$(EXTENSION)-$(DISTVERSION)/ -o $(EXTENSION)-$(DISTVERSION).zip HEAD

test_dump_restore: TEST_DUMP_RESTORE_OPTIONS?=
test_dump_restore: $(CURDIR)/bin/test_dump_restore.sh sql/test_dump_restore.sql
	PGDATABASE=test_dump_restore \
		$< --extension $(EXTENSION) \
		$(TEST_DUMP_RESTORE_OPTIONS) \
		--psql-script-file sql/test_dump_restore.sql \
		--out-file results/test_dump_restore.out \
		--expected-out-file expected/test_dump_restore.out
