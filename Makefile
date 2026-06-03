GODOT ?= godot

.PHONY: test run test-verbose test-stage

test:
	$(GODOT) --headless -s addons/gut/gut_cmdln.gd

run:
	$(GODOT)

test-verbose:
	$(GODOT) --headless -s addons/gut/gut_cmdln.gd -glog=3

test-stage:
	@if [ -z "$(STAGE)" ]; then echo "Usage: make test-stage STAGE=1"; exit 1; fi
	$(GODOT) --headless -s addons/gut/gut_cmdln.gd -gselect=stage$(STAGE)
