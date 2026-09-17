# docs/architecture.md §15. The point of these targets is that the two knobs which must agree —
# Gradle's --flavor and Dart's --dart-define=BRAND — are set from one variable, and that
# `analyze` runs the command that actually executes import_lint (§3.3: NOT flutter analyze).

FLUTTER := ~/fvm/versions/3.44.6/bin/flutter
DART    := ~/fvm/versions/3.44.6/bin/dart

.PHONY: run apk test goldens analyze format

## run BRAND=retail — debug the app for one Brand
run:
ifndef BRAND
	$(error BRAND is required, e.g. `make run BRAND=retail`)
endif
	$(FLUTTER) run --flavor $(BRAND) --dart-define=BRAND=$(BRAND)

## apk BRAND=utility — release APK for one Brand
apk:
ifndef BRAND
	$(error BRAND is required, e.g. `make apk BRAND=utility`)
endif
	$(FLUTTER) build apk --flavor $(BRAND) --dart-define=BRAND=$(BRAND)

## test — the whole suite except the goldens (they are platform-sensitive)
test:
	$(FLUTTER) test --exclude-tags golden

## goldens — regenerate the per-Brand reference images, then review them by eye
goldens:
	$(FLUTTER) test --tags golden --update-goldens

## analyze — the real lint. `flutter analyze` silently skips import_lint
analyze:
	$(DART) analyze --fatal-infos

## format
format:
	$(DART) format lib test integration_test
