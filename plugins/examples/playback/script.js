function node(tag, className, text) {
  const element = document.createElement(tag);
  if (className) element.className = className;
  if (text) element.textContent = text;
  return element;
}
function render(state) {
  const media = state && state.media;
  const el = document.getElementById('content');
  el.innerHTML = '';
  if (!media || !media.hasSession) {
    el.appendChild(node('div', 'body dim', 'No media session'));
    return;
  }
  el.appendChild(node('div', 'media-title', media.title || 'Unknown track'));
  el.appendChild(node('div', 'body', media.artist || ''));
  if (media.album) el.appendChild(node('div', 'body dim', media.album));
  el.appendChild(node('div', 'body', media.playing ? 'Playing' : 'Paused'));
  const row = node('div', 'controls');
  const buttons = [
    ['mediaPrevious', 'Prev'],
    ['mediaPlayPause', media.playing ? 'Pause' : 'Play'],
    ['mediaNext', 'Next']
  ];
  buttons.forEach(function (entry) {
    const button = node('button', null, entry[1]);
    button.addEventListener('click', function () { host.action(entry[0]).catch(function () {}); });
    row.appendChild(button);
  });
  el.appendChild(row);
}
host.getConfig().then(applyPluginTheme).catch(() => {});
host.onState(render);
host.getState().then(render).catch(() => render(null));
