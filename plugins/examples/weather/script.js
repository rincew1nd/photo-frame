let config = {};
function render(state) {
  const w = state && state.weather;
  const el = document.getElementById('content');
  if (!w) { el.innerHTML = '<div class="body dim">No weather data</div>'; return; }
  const symbol = (w.unit || 'celsius') === 'fahrenheit' ? '°F' : '°C';
  el.innerHTML = '<div class="value">' + Math.round(w.temperature) + symbol +
    '</div><div class="body">' + (w.description || '') + '</div><div class="body dim">' + (w.locationLabel || '') + '</div>';
}
host.getConfig().then(c => { config = c || {}; applyPluginTheme(config); }).catch(() => {});
host.onState(render);
host.getState().then(render).catch(() => render(null));
