EXTENSION = pg_safer_settings_table_dependent_subextension

DATA = $(wildcard $(EXTENSION)*.sql)

REGRESS = $(EXTENSION)

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
