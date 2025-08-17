PLUGIN_NAME := tview
PLUGIN_DIR  := plugin

.PHONY: lint
lint:
	bash -n $(PLUGIN_DIR)/tview.sh

.PHONY: install
install: lint
	mkdir -p "$(HELM_PLUGINS)"
	rm -rf "$(HELM_PLUGINS)/$(PLUGIN_NAME)"
	cp -R $(PLUGIN_DIR) "$(HELM_PLUGINS)/$(PLUGIN_NAME)"

.PHONY: package
package: lint
	tar -C $(PLUGIN_DIR) -czf $(PLUGIN_NAME)-$(shell grep '^version:' $(PLUGIN_DIR)/plugin.yaml | awk '{print $$2}').tgz .
