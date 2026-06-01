# All targets are meant to be invoked from the repo root via `make -C app <target>`.
# Every target runs Flutter/Dart through fvm so the pinned SDK in .fvmrc is used.

FLUTTER := fvm flutter
DART := fvm dart

.PHONY: help install get scaffold-linux scaffold-android analyze test fmt format build build-apk run run-android doctor devices clean

help:
	@echo "Targets (run from repo root as 'make -C app <target>'):"
	@echo "  install        Install the pinned Flutter SDK (reads .fvmrc)"
	@echo "  get            flutter pub get"
	@echo "  scaffold-linux Generate the linux/ desktop runner (additive)"
	@echo "  scaffold-android  Generate the Android platform folder"
	@echo "  analyze        Static analysis (flutter analyze)"
	@echo "  test           Run all Flutter tests"
	@echo "  fmt            Format Dart sources in place (dart format)"
	@echo "  format         Verify formatting, fail if changes needed (CI)"
	@echo "  build          Build the Linux desktop bundle (compiles native libs)"
	@echo "  build-apk         Build a debug APK"
	@echo "  run            Run on the Linux desktop target"
	@echo "  run-android       Run on a connected Android device"
	@echo "  doctor         flutter doctor -v"
	@echo "  devices        List devices (expect a linux device)"
	@echo "  clean          flutter clean"

install:
	fvm install

get:
	$(FLUTTER) pub get

scaffold-linux:
	$(FLUTTER) create --platforms=linux --org io.github.psychonaut0 --project-name workout_tracker .

scaffold-android:
	$(FLUTTER) create --platforms=android --org dev.psy --project-name workout_tracker .

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

build-apk:
	$(FLUTTER) build apk --debug

run:
	$(FLUTTER) run -d linux

run-android:
	$(FLUTTER) run -d android

doctor:
	$(FLUTTER) doctor -v

devices:
	$(FLUTTER) devices

clean:
	$(FLUTTER) clean
