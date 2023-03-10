EXTENSION = pg_safer_settings

DISTVERSION = $(shell sed -n -E "/default_version/ s/^.*'(.*)'.*$$/\1/p" $(EXTENSION).control)

DATA = $(wildcard sql/$(EXTENSION)--*.sql)

REGRESS = tap_tests

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

README.md: sql/README.sql install
	psql --quiet postgres < $< > $@

META.json: sql/META.sql install
	psql --quiet postgres < $< > $@

dist: META.json README.md
	git archive --format zip --prefix=$(EXTENSION)-$(DISTVERSION)/ -o $(EXTENSION)-$(DISTVERSION).zip HEAD

test_dump_restore: $(CURDIR)/test_dump_restore.sh sql/test_dump_restore.sql
	PGDATABASE=test_dump_restore \
		$< --extension $(EXTENSION) \
		--psql-script-file sql/test_dump_restore.sql \
		--out-file results/test_dump_restore.out \
		--expected-out-file expected/test_dump_restore.out
