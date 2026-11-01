function render(state) {
  const now = state && state.time ? new Date(state.time.epochMs) : new Date();
  document.getElementById('content').innerHTML =
    '<div class="value">' + now.toLocaleDateString(undefined, { weekday: 'long' }) +
    '</div><div class="body">' + now.toLocaleDateString() + '</div>';
}
host.getConfig().then(applyPluginTheme).catch(() => {});
host.onState(render);
host.getState().then(render).catch(() => render(null));
