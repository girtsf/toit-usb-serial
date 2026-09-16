# Uses the plain `toit` executable if available, falling back to `jag toit`.
# Override with e.g. `make TOIT="path/to/toit"`.
TOIT ?= $(shell command -v toit > /dev/null && echo toit || echo jag toit)

all: test analyze

install-pkgs:
	$(TOIT) pkg install
	cd tests && $(TOIT) pkg install

test: install-pkgs
	@for test in tests/*-test.toit; do \
		echo "Running $$test"; \
		$(TOIT) run "$$test" || exit 1; \
	done

analyze:
	$(TOIT) analyze src/*.toit
	cd tests && $(TOIT) analyze *.toit

.PHONY: all install-pkgs test analyze
