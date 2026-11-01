let config = {};
function render() {
  const d = new Date();
  const hour = config.format === '12h' ? ((d.getHours() + 11) % 12) + 1 : d.getHours();
  const suffix = config.format === '12h' ? (d.getHours() >= 12 ? ' PM' : ' AM') : '';
  const text = String(hour).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0') + suffix;
  document.getElementById('content').innerHTML =
    '<div class="value" style="color:' + (config.color || '#fff') + '">' + text + '</div>';
}
host.getConfig().then(c => { config = c || {}; applyPluginTheme(config); render(); }).catch(() => render());
host.onState(() => render());
setInterval(render, 1000);
