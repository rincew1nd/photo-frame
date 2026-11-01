# Plugin Playground

A standalone browser dev tool for the Photo Frame plugin API. It loads a plugin
into a sandboxed iframe, mocks the host bridge, and shows console/bridge logs.

## Run

From the repo root:

```powershell
python -m http.server 8000
```

Open <http://localhost:8000/plugins/playground/>.

Examples are fetched from `plugins/examples/`, so they need the HTTP server.
Folder loading works from `file://` too: open `plugins/playground/index.html` in
a browser and use **Load folder** on a plugin source folder.

## Use

- Pick an example and press **Load example**. `playback` loads on startup.
- Edit files in **Source**; auto-run rebuilds the preview after 500 ms.
- **Ctrl+Enter** (or **Run**) rebuilds immediately.
- **Inputs** edits the mocked state/config JSON. Invalid JSON is rejected
  without replacing the last valid mock.
- **Logs** captures console output, `host.log`, actions, storage, network,
  links, errors, and preview reloads.
- The preview is an `<iframe sandbox="allow-scripts">` built from `srcdoc`.
  CSS and JS referenced by the entry are inlined; paths are resolved relative
  to the entry.

Network requests are denied, links are only logged, and storage is in-memory
per loaded plugin.
