# Установочные пути (можно переопределять: make PREFIX=/opt install)
PREFIX        ?= /usr/local
BINDIR        ?= $(PREFIX)/bin
SYSTEMD_DIR   ?= /etc/systemd/system
ENV_DIR       ?= /etc/test-monitor
LOGROTATE_DIR ?= /etc/logrotate.d
STATE_DIR     ?= /var/lib/test-monitor
LOG_FILE      ?= /var/log/monitoring.log
LOCK_DIR      ?= /run/lock

SERVICE_NAME  := test-monitor
SERVICE_FILE  := $(SERVICE_NAME).service
TIMER_FILE    := $(SERVICE_NAME).timer
ENV_FILE_NAME := $(SERVICE_NAME).env
LOGROTATE_CFG := $(SERVICE_NAME)

INSTALL_BIN   := $(BINDIR)/$(SERVICE_NAME).sh
INSTALL_SVC   := $(SYSTEMD_DIR)/$(SERVICE_FILE)
INSTALL_TMR   := $(SYSTEMD_DIR)/$(TIMER_FILE)
INSTALL_ENV   := $(ENV_DIR)/$(ENV_FILE_NAME)
INSTALL_LR    := $(LOGROTATE_DIR)/$(LOGROTATE_CFG)

.PHONY: all install uninstall enable disable start stop status logs test lint

all:
	@echo "Targets: install | uninstall | enable | disable | start | stop | status | logs | test | lint"

install:
	@echo "Installing (need root)..."
	install -d "$(BINDIR)" "$(SYSTEMD_DIR)" "$(ENV_DIR)" "$(LOGROTATE_DIR)" "$(STATE_DIR)" "$(LOCK_DIR)"
	install -m 0755 bin/$(SERVICE_NAME).sh "$(INSTALL_BIN)"
	install -m 0644 systemd/$(SERVICE_FILE) "$(INSTALL_SVC)"
	install -m 0644 systemd/$(TIMER_FILE) "$(INSTALL_TMR)"
	@if [ ! -f "$(INSTALL_ENV)" ]; then install -m 0644 systemd/$(ENV_FILE_NAME) "$(INSTALL_ENV)"; else echo "Keep existing $(INSTALL_ENV)"; fi
	install -m 0644 logrotate/$(LOGROTATE_CFG) "$(INSTALL_LR)"
	touch "$(LOG_FILE)"; chmod 0644 "$(LOG_FILE)"
	systemctl daemon-reload
	systemctl enable --now $(TIMER_FILE)
	@echo "Installed. See: make status | make logs"

uninstall:
	@echo "Uninstalling (need root)..."
	- systemctl disable --now $(TIMER_FILE) 2>/dev/null || true
	- systemctl stop $(SERVICE_FILE) 2>/dev/null || true
	- rm -f "$(INSTALL_SVC)" "$(INSTALL_TMR)" "$(INSTALL_BIN)" "$(INSTALL_LR)"
	- systemctl daemon-reload
	@echo "NOTE: $(INSTALL_ENV), $(STATE_DIR) и $(LOG_FILE) не удалены; удалите вручную при необходимости."

enable:
	systemctl enable --now $(TIMER_FILE)

disable:
	systemctl disable --now $(TIMER_FILE)

start:
	systemctl start $(SERVICE_FILE)

stop:
	systemctl stop $(SERVICE_FILE)

status:
	systemctl status --no-pager $(SERVICE_FILE) || true
	systemctl status --no-pager $(TIMER_FILE) || true

logs:
	journalctl -u $(SERVICE_FILE) -n 100 --no-pager || true
	@echo "tail of $(LOG_FILE):"
	@- tail -n 50 "$(LOG_FILE)" || true

test:
	@echo "One-shot run of the service..."
	systemctl start $(SERVICE_FILE)
	@echo "Done. See 'make logs'"

lint:
	@command -v shellcheck >/dev/null && shellcheck -x bin/$(SERVICE_NAME).sh || echo "shellcheck not installed (skip)"
