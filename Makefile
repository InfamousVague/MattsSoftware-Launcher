# MattsSoftware suite — build / bump / release every menu-bar app
# from one place. The sibling app repos live next to this launcher
# repo (../Alfred, ../quarantine-swift, ../sentry-swift, …).
#
# This Makefile is the friendly front door; the orchestration lives
# in scripts/suite.sh (bash 3.2 compatible). Every app is Developer
# ID signed + Apple-notarized + stapled, and its .dmg wraps the
# already-stapled .app, so the suite opens on any Mac.
#
#   make versions                 every app's current version
#   make build                    build/sign/notarize/staple all 7
#   make bump                     patch-bump all 7
#   make release                  build + commit bump + push + GH release (all 7)
#   make ship                     bump + release (all 7)
#   make clean                    remove built .app/.dmg/dist artifacts
#   make build-Sentry             one app (also bump-/release-<App>)
#
# Apps: Alfred Quarantine Espresso Sentry Peephole Port MattsSoftware

SHELL := /bin/bash
SUITE := scripts/suite.sh

.DEFAULT_GOAL := help
.PHONY: help build bump release ship versions clean

help:
	@echo "MattsSoftware suite — all 7 menu-bar apps"
	@echo
	@echo "  make versions          show each app's current version"
	@echo "  make build             build + sign + notarize + staple every app"
	@echo "  make bump              patch-bump every app's version"
	@echo "  make release           build, commit the bump, push, GitHub release"
	@echo "  make ship              bump + release in one pass"
	@echo "  make clean             remove built .app/.dmg/dist artifacts"
	@echo
	@echo "  single app:  make build-Sentry | bump-Port | release-Quarantine"
	@echo "  apps:        Alfred Quarantine Espresso Sentry Peephole Port MattsSoftware"

build:    ; @$(SUITE) build
bump:     ; @$(SUITE) bump
release:  ; @$(SUITE) release
versions: ; @$(SUITE) versions
clean:    ; @$(SUITE) clean
ship:     ; @$(SUITE) bump && $(SUITE) release

# Per-app targets: make build-Sentry / bump-Port / release-Quarantine
build-%:   ; @$(SUITE) build $*
bump-%:    ; @$(SUITE) bump $*
release-%: ; @$(SUITE) release $*
