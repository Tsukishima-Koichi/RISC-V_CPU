# Makefile: batch convert 32-bit irom COE files to 64-bit for dual-issue BRAM
#
# Targets:
#   make          - convert ALL irom.coe -> irom_64b.coe (recursive)
#   make T=<dir>  - convert only irom.coe under specific subdirectory
#   make clean    - delete all generated *_64b.coe files
#   make list     - show all irom.coe files found

PYTHON  := python3
SCRIPT  := conv_coe_32to64.py
ROOT    := .

# Find all irom.coe files under ROOT (recursive)
IROM_SRCS := $(shell find $(ROOT) -name "irom.coe" -type f | sort)
IROM_DSTS := $(IROM_SRCS:%.coe=%_64b.coe)

.PHONY: all list clean

all: $(IROM_DSTS)
	@echo "Done. Converted $(words $(IROM_DSTS)) file(s)."

list:
	@echo "irom.coe files found:"
	@for f in $(IROM_SRCS); do echo "  $$f"; done
	@echo "Total: $(words $(IROM_SRCS))"

clean:
	@echo "Removing generated files..."
	@find $(ROOT) -name "irom_64b.coe" -type f -delete
	@echo "Done."

# Pattern rule: irom.coe -> irom_64b.coe
%_64b.coe: %.coe $(SCRIPT)
	@$(PYTHON) $(SCRIPT) $< $@
