let config = { showTags: true };
function render(state) {
  const image = state && state.image;
  const el = document.getElementById('content');
  if (!image) { el.textContent = 'No image'; return; }
  const lines = [];
  if (image.exifDate) lines.push(new Date(image.exifDate).toLocaleDateString());
  if (image.description) lines.push(image.description);
  if (image.location) lines.push(image.location);
  if (config.showTags && image.tags && image.tags.length) lines.push(image.tags.join(' · '));
  el.innerHTML = lines.map(l => '<div class="body">' + l + '</div>').join('');
}
host.getConfig().then(c => { config = c || config; applyPluginTheme(config); }).catch(() => {});
host.onState(render);
host.getState().then(render).catch(() => render(null));
