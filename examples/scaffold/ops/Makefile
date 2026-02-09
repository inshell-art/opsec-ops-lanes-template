SHELL := /bin/bash

ROOT := $(shell git rev-parse --show-toplevel)
NETWORK ?=
RUN_ID ?=
LANE ?= lane1

.PHONY: bundle verify approve apply subtree-update

bundle:
	NETWORK=$(NETWORK) LANE=$(LANE) RUN_ID=$(RUN_ID) $(ROOT)/ops/tools/bundle.sh

verify:
	NETWORK=$(NETWORK) RUN_ID=$(RUN_ID) $(ROOT)/ops/tools/verify_bundle.sh

approve:
	NETWORK=$(NETWORK) RUN_ID=$(RUN_ID) $(ROOT)/ops/tools/approve_bundle.sh

apply:
	NETWORK=$(NETWORK) RUN_ID=$(RUN_ID) $(ROOT)/ops/tools/apply_bundle.sh

subtree-update:
	$(ROOT)/ops/tools/update_ops_template.sh
