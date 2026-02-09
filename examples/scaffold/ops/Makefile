SHELL := /bin/bash

ROOT := $(shell git rev-parse --show-toplevel)
NETWORK ?=
RUN_ID ?=
LANE ?= lane1

.PHONY: plan check approve apply bundle verify-bundle approve-bundle apply-bundle

plan:
	$(ROOT)/ops/tools/plan.sh

check:
	$(ROOT)/ops/tools/check.sh

approve:
	$(ROOT)/ops/tools/approve.sh

apply:
	$(ROOT)/ops/tools/apply.sh

bundle:
	NETWORK=$(NETWORK) LANE=$(LANE) RUN_ID=$(RUN_ID) $(ROOT)/ops/tools/bundle.sh

verify-bundle:
	NETWORK=$(NETWORK) RUN_ID=$(RUN_ID) $(ROOT)/ops/tools/verify_bundle.sh

approve-bundle:
	NETWORK=$(NETWORK) RUN_ID=$(RUN_ID) $(ROOT)/ops/tools/approve_bundle.sh

apply-bundle:
	NETWORK=$(NETWORK) RUN_ID=$(RUN_ID) $(ROOT)/ops/tools/apply_bundle.sh
