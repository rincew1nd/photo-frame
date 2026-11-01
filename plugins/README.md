# Bundled Example Plugins

Source and packaged assets for the examples that ship with Photo Frame.

```
plugins/
  examples/<name>/   source: plugin.json, index.html, styles.css, common.js, script.js
  zips/<name>.zip    packaged assets loaded by the app
  package_examples.ps1
```

Edit the files under `examples/`, then package them:

```powershell
pwsh -NoProfile -File plugins/package_examples.ps1
```

The script zips each source folder to `zips/<name>.zip` with the files at the
ZIP root. Do not hand-edit `zips/`; regenerate it from `examples/`.

To add an example, create `examples/<name>/` with the required files, package,
and register the ID in `lib/data/plugins/bundled_examples.dart`.
