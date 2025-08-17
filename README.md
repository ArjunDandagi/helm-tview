# helm-tview (Helm TUI template viewer)

A Helm plugin that renders `helm template` output into files and lets you browse them in a split-view TUI. Left shows a readable file list; right shows a syntax-highlighted preview.

- Left panel: bold filename, dimmed directory, cyan Kubernetes kind (if found)
- Right panel: `bat`-powered preview (or `less` fallback)
- Works with `fzf`; falls back to a simple menu if unavailable

## Install

```bash
# Using git clone (recommended for development)
git clone https://github.com/arjundandagi/helm-tview
cd helm-tview
make install  # copies to your Helm plugin dir

# Or copy manually
mkdir -p "$HELM_PLUGINS"
cp -R plugin "$HELM_PLUGINS/tview"
```

Check:
```bash
helm plugin list
```

## Usage

```bash
# from inside a chart directory (must contain Chart.yaml)
helm tview .

# or specify release and chart
helm tview myrel ./path/to/chart -f values.yaml
```

## Requirements

- Helm 3+
- Optional: `fzf` and `bat` for best UX
  - macOS: `brew install fzf bat`

## Development

Layout:
```
plugin/
  plugin.yaml
  tview.sh
```

### Lint
```bash
bash -n plugin/tview.sh
```

### Run without installing
```bash
export HELM_PLUGINS="$(pwd)"
helm plugin list
helm tview .
```

## Release (GitHub Actions)

Tagging `vX.Y.Z` on `main` will:
- Package `plugin/` directory as `tview-vX.Y.Z.tgz`
- Upload to the release assets

Users can then install via:
```bash
helm plugin install https://github.com/arjundandagi/helm-tview --version vX.Y.Z
```
