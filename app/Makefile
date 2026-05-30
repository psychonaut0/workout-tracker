# All targets are meant to be invoked from the repo root via `make -C app <target>`.
# Every target runs Flutter/Dart through fvm so the pinned SDK in .fvmrc is used.

FLUTTER := fvm flutter
DART := fvm dart

.PHONY: help install get scaffold-linux analyze test fmt format build run doctor devices clean

help:
	@echo "Targets (run from repo root as 'make -C app <target>'):"
	@echo "  install        Install the pinned Flutter SDK (reads .fvmrc)"
	@echo "  get            flutter pub get"
	@echo "  scaffold-linux Generate the linux/ desktop runner (additive)"
	@echo "  analyze        Static analysis (flutter analyze)"
	@echo "  test           Run all Flutter tests"
	@echo "  fmt            Format Dart sources in place (dart format)"
	@echo "  format         Verify formatting, fail if changes needed (CI)"
	@echo "  build          Build the Linux desktop bundle (compiles native libs)"
	@echo "  run            Run on the Linux desktop target"
	@echo "  doctor         flutter doctor -v"
	@echo "  devices        List devices (expect a linux device)"
	@echo "  clean          flutter clean"

install:
	fvm install

get:
	$(FLUTTER) pub get

scaffold-linux:
	$(FLUTTER) create --platforms=linux --org tech.travelware --project-name workout_tracker .

analyze:
	$(FLUTTER) analyze

test:
	$(FLUTTER) test

fmt:
	$(DART) format .

format:
	$(DART) format --output=none --set-exit-if-changed .

build:
	$(FLUTTER) build linux

run:
	$(FLUTTER) run -d linux

doctor:
	$(FLUTTER) doctor -v

devices:
	$(FLUTTER) devices

clean:
	$(FLUTTER) clean
