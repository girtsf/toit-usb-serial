# Uses the plain `toit` executable if available, falling back to `jag toit`.
# Override with e.g. `make TOIT="path/to/toit"`.
TOIT ?= $(shell command -v toit > /dev/null && echo toit || echo jag toit)

all: test analyze

install-pkgs:
	$(TOIT) pkg install
	cd tests && $(TOIT) pkg install
	cd examples && $(TOIT) pkg install

test: install-pkgs
	@for test in tests/*-test.toit; do \
		echo "Running $$test"; \
		$(TOIT) run "$$test" || exit 1; \
	done

# One file per call: files from different project roots can resolve imports
# wrongly when analyzed together.
analyze: install-pkgs
	@for file in src/*.toit tests/*.toit tests/hw/*.toit examples/*.toit; do \
		echo "Analyzing $$file"; \
		$(TOIT) analyze "$$file" || exit 1; \
	done

.PHONY: all install-pkgs test analyze
