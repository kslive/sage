# ─────────────────────────────────────────────────────────────
# Sage — сборка нативного macOS-приложения (Tuist + Xcode beta)
# ─────────────────────────────────────────────────────────────

export DEVELOPER_DIR := /Applications/Xcode-beta.app/Contents/Developer
export PATH := /opt/homebrew/bin:$(HOME)/.local/share/mise/shims:$(PATH)

TUIST    := mise exec -- tuist
APP_NAME := Sage
# Идентичность подписи релиза: стабильный self-signed сертификат (общий с Ember) —
# подпись не меняется между сборками, Keychain/TCC не переспрашивают после обновлений.
SIGN_ID  ?= Ember Signing
SCHEME   := Sage
WORKSPACE := $(APP_NAME).xcworkspace
DERIVED  := Build
DIST     := dist
CONFIG   ?= Debug

DEST := -destination 'platform=macOS,arch=arm64'
UNSIGNED := CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER=""
STAMP := $(shell date +%s)

.DEFAULT_GOAL := help
.PHONY: help bootstrap generate open build run test lint format clean release install reset reset-state editor-build editor-test editor-install

help: ## Список команд
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

bootstrap: ## Установить инструменты (Tuist/SwiftLint/SwiftFormat)
	brew install swiftlint swiftformat mise || true
	mise install

generate: ## Сгенерировать Xcode-проект (без открытия)
	$(TUIST) install || true
	$(TUIST) generate --no-open

open: ## Сгенерировать и открыть в Xcode
	$(TUIST) generate

build: generate ## Собрать (CONFIG=Debug|Release)
	xcodebuild -workspace $(WORKSPACE) -scheme $(SCHEME) -configuration $(CONFIG) \
		-derivedDataPath $(DERIVED) $(DEST) $(UNSIGNED) build | xcbeautify 2>/dev/null || \
	xcodebuild -workspace $(WORKSPACE) -scheme $(SCHEME) -configuration $(CONFIG) \
		-derivedDataPath $(DERIVED) $(DEST) $(UNSIGNED) build

run: build ## Собрать (Debug) и запустить
	open "$(DERIVED)/Build/Products/$(CONFIG)/$(APP_NAME).app"

test: generate ## Прогнать юнит-тесты (Swift)
	$(TUIST) test

editor-build: ## Пересобрать JS-редактор (CodeMirror) → Resources/editor/editor.js
	cd Projects/EditorFeature/editor-src && npm run build

editor-test: ## Юнит-тесты JS-редактора (node:test + jsdom)
	cd Projects/EditorFeature/editor-src && npm test

editor-install: ## npm install для редактора (CM6 + esbuild + jsdom)
	cd Projects/EditorFeature/editor-src && npm install

lint: ## SwiftLint
	swiftlint lint --quiet

format: ## SwiftFormat (изменяет файлы)
	swiftformat Projects Tuist Project.swift Tuist.swift

clean: ## Очистить артефакты
	$(TUIST) clean || true
	rm -rf $(DERIVED) $(DIST) Derived *.xcworkspace *.xcodeproj

release: ## Release-сборка → неподписанный .app в dist/ (новый штамп сборки)
	$(MAKE) generate
	xcodebuild -workspace $(WORKSPACE) -scheme $(SCHEME) -configuration Release \
		-derivedDataPath $(DERIVED) $(DEST) $(UNSIGNED) CURRENT_PROJECT_VERSION=$(STAMP) build
	rm -rf $(DIST) && mkdir -p $(DIST)
	cp -R "$(DERIVED)/Build/Products/Release/$(APP_NAME).app" "$(DIST)/"
	# MLX ищет mlx.metallib (рядом с бинарём / Resources/mlx.metallib), а в бандле он default.metallib.
	# Кладём копию под нужным именем ДО подписи, иначе MLX падает: "Failed to load the default metallib".
	@MLIB="$(DIST)/$(APP_NAME).app/Contents/Frameworks/Cmlx.framework/Versions/A/Resources"; \
	if [ -f "$$MLIB/default.metallib" ]; then cp -f "$$MLIB/default.metallib" "$$MLIB/mlx.metallib"; echo "🔧 metallib: mlx.metallib создан"; else echo "⚠️ default.metallib не найден в $$MLIB"; fi
	# Стабильная подпись (как в Ember): self-signed сертификат не меняется между сборками →
	# Keychain/TCC продолжают доверять приложению после обновления. Фолбэк — ad-hoc.
	@if security find-identity -v -p codesigning 2>/dev/null | grep -q "$(SIGN_ID)"; then \
		codesign --force --deep --sign "$(SIGN_ID)" "$(DIST)/$(APP_NAME).app"; \
		echo "🔏 Подписано: $(SIGN_ID)"; \
	else \
		codesign --force --deep --sign - "$(DIST)/$(APP_NAME).app"; \
		echo "⚠️  $(SIGN_ID) не найден — подписано ad-hoc"; \
	fi
	xattr -cr "$(DIST)/$(APP_NAME).app"
	@echo "✅ Готово: $(DIST)/$(APP_NAME).app"

reset reset-state: ## Полностью сбросить состояние приложения (настройки + модели + чаты) — для теста онбординга с нуля
	defaults delete com.sage.app 2>/dev/null || true
	rm -rf "$(HOME)/Library/Application Support/Sage"
	@echo "🧹 Состояние Sage сброшено (онбординг при следующем запуске)"

install: release ## Установить в /Applications (состояние СОХРАНЯЕТСЯ; для сброса — make reset)
	rm -rf "/Applications/$(APP_NAME).app"
	cp -R "$(DIST)/$(APP_NAME).app" /Applications/
	xattr -dr com.apple.quarantine "/Applications/$(APP_NAME).app" || true
	@echo "✅ Установлено: /Applications/$(APP_NAME).app (модели/онбординг/хранилище сохранены)"

package: release ## Упаковать dist/Sage.app → zip + sha256 (ассеты для GitHub-релиза = OTA-фид)
	@VER=$$(grep MARKETING_VERSION Tuist/ProjectDescriptionHelpers/Module.swift | head -1 | sed -E 's/.*"([0-9.]+)".*/\1/'); \
	cd "$(DIST)" && ditto -c -k --sequesterRsrc --keepParent "$(APP_NAME).app" "$(APP_NAME)-$$VER.zip"; \
	shasum -a 256 "$(APP_NAME)-$$VER.zip" | awk '{print $$1}' > "$(APP_NAME)-$$VER.zip.sha256"; \
	echo "📦 dist/$(APP_NAME)-$$VER.zip (+ .sha256) — залить в GitHub Release v$$VER (SHA256 также в тело релиза)"
