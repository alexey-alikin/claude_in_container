WRAPPER     := $(CURDIR)/claude.sh
INSTALL_DIR := $(HOME)/.local/bin
INSTALL_BIN := $(INSTALL_DIR)/cic

.DEFAULT_GOAL := help

.PHONY: help install uninstall

help:
	@echo "claude_in_container — make targets"
	@echo
	@echo "  make install    install $(INSTALL_BIN) launcher pointing to $(WRAPPER)"
	@echo "  make uninstall  remove the launcher (only if it points to this repo)"
	@echo "  make help       show this help (default)"

install:
	@if [ ! -f "$(WRAPPER)" ]; then \
		echo "error: $(WRAPPER) not found" >&2; \
		exit 1; \
	fi
	@mkdir -p "$(INSTALL_DIR)"
	@printf '%s\n' \
		'#!/usr/bin/env bash' \
		'# Installed by claude_in_container Makefile. Safe to remove with `make uninstall`.' \
		'exec "$(WRAPPER)" "$$@"' \
		> "$(INSTALL_BIN)"
	@chmod +x "$(INSTALL_BIN)"
	@echo "installed $(INSTALL_BIN) -> $(WRAPPER)"
	@case ":$$PATH:" in \
		*":$(INSTALL_DIR):"*) ;; \
		*) echo "warning: $(INSTALL_DIR) is not in your PATH."; \
		   echo "         add this to your shell rc:"; \
		   echo "             export PATH=\"$(INSTALL_DIR):\$$PATH\"" ;; \
	esac

uninstall:
	@if [ ! -e "$(INSTALL_BIN)" ]; then \
		echo "$(INSTALL_BIN) not installed; nothing to do"; \
		exit 0; \
	fi
	@if grep -qxF 'exec "$(WRAPPER)" "$$@"' "$(INSTALL_BIN)"; then \
		rm "$(INSTALL_BIN)"; \
		echo "removed $(INSTALL_BIN)"; \
	else \
		echo "error: $(INSTALL_BIN) exists but does not reference $(WRAPPER); refusing to remove" >&2; \
		exit 1; \
	fi
