function render(state) {
  const image = state && state.image;
  const el = document.getElementById('content');
  if (!image) { el.textContent = 'No image'; return; }
  el.innerHTML = '<div class="value">' + (image.width || '?') + ' × ' +
    (image.height || '?') + '</div><div class="body">' + (image.type || '') + ' · ' +
    (image.mimeType || '') + '</div><div class="body dim">' + (image.cached ? 'Cached' : 'Remote') + '</div>';
}
host.getConfig().then(applyPluginTheme).catch(() => {});
host.onState(render);
host.getState().then(render).catch(() => render(null));
