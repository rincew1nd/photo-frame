$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = Join-Path $PSScriptRoot '..\assets\plugins'
New-Item -ItemType Directory -Force -Path $root | Out-Null
$temp = Join-Path ([System.IO.Path]::GetTempPath()) ('photoframe_examples_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $temp | Out-Null

function New-Example {
  param(
    [string]$Name,
    [string]$Manifest,
    [string]$Html,
    [string]$Css,
    [string]$Js
  )
  $dir = Join-Path $temp $Name
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  Set-Content -LiteralPath (Join-Path $dir 'plugin.json') -Value $Manifest -Encoding utf8NoBOM
  Set-Content -LiteralPath (Join-Path $dir 'index.html') -Value $Html -Encoding utf8NoBOM
  Set-Content -LiteralPath (Join-Path $dir 'styles.css') -Value $Css -Encoding utf8NoBOM
  Set-Content -LiteralPath (Join-Path $dir 'common.js') -Value $commonJs -Encoding utf8NoBOM
  Set-Content -LiteralPath (Join-Path $dir 'script.js') -Value $Js -Encoding utf8NoBOM
  $zip = Join-Path $root "$Name.zip"
  if (Test-Path $zip) { Remove-Item $zip }
  [System.IO.Compression.ZipFile]::CreateFromDirectory($dir, $zip)
}

$css = @'
html, body { margin: 0; width: 100%; height: 100%; background: transparent; overflow: hidden; }
.card { box-sizing: border-box; width: 100%; height: 100%; padding: 8px 10px;
  display: flex; flex-direction: column; justify-content: center;
  background: rgba(0,0,0,0.8); border-radius: 2em;
  color: #fff; font-family: "Segoe UI", sans-serif;
  text-shadow: 0 2px 14px rgba(0,0,0,0.78), 0 0 2px rgba(0,0,0,0.55); }
.value { font-size: 40px; font-weight: 300; line-height: 1; letter-spacing: -0.02em; }
.media-title { font-size: 30px; font-weight: 300; line-height: 1.05; letter-spacing: -0.02em; }
.body { font-size: 14px; line-height: 1.35; opacity: 0.92; }
.dim { font-size: 12px; opacity: 0.68; }
.controls { display: flex; gap: 6px; margin-top: 6px; }
.controls button { flex: 1; padding: 4px 6px; border: 0; border-radius: 6px;
  background: rgba(255,255,255,0.16); color: #fff; font: inherit; cursor: pointer; }
.controls button:active { background: rgba(255,255,255,0.32); }
'@

$commonJs = @'
(function () {
  'use strict';
  function rgba(hex, opacity) {
    var value = typeof hex === 'string' ? hex.replace('#', '') : '';
    if (value.length === 8) { value = value.slice(2); }
    if (value.length !== 6) { value = '000000'; }
    var alpha = typeof opacity === 'number' ? Math.min(1, Math.max(0, opacity)) : 0.8;
    return 'rgba(' + parseInt(value.slice(0, 2), 16) + ',' +
      parseInt(value.slice(2, 4), 16) + ',' +
      parseInt(value.slice(4, 6), 16) + ',' + alpha + ')';
  }
  window.applyPluginTheme = function (config) {
    var card = document.querySelector('.card');
    if (!card) { return; }
    config = config || {};
    card.style.background = rgba(config.backgroundColor, config.backgroundOpacity);
    var radius = typeof config.cornerRadius === 'number' ? config.cornerRadius : 2;
    card.style.borderRadius = Math.min(8, Math.max(0, radius)) + 'em';
  };
})();
'@

$html = @'
<!doctype html>
<html><head><meta charset="utf-8"><link rel="stylesheet" href="styles.css"></head>
<body><div class="card"><div id="content" class="body">Loading...</div></div>
<script src="common.js"></script><script src="script.js"></script></body></html>
'@

$themeSettings = @'
    "backgroundColor": { "type": "color", "label": "Background color", "default": "#000000" },
    "backgroundOpacity": { "type": "number", "label": "Background opacity", "default": 0.8, "min": 0, "max": 1, "step": 0.05 },
    "cornerRadius": { "type": "number", "label": "Corner radius", "default": 2, "min": 0, "max": 8, "step": 0.5 }
'@

$clockManifest = @"
{
  "id": "com.rincew1nd.photoframe.clock",
  "name": "Clock",
  "version": "1.0.0",
  "apiVersion": 1,
  "minAppVersion": "1.0.0",
  "author": "Photo Frame",
  "license": "MIT",
  "description": "A configurable clock overlay.",
  "entry": "index.html",
  "permissions": { "network": false },
  "inputs": ["time", "config"],
  "placement": { "anchor": "top-start", "x": 0.04, "y": 0.06, "width": 220, "height": 88, "zOrder": 10, "showDuringNight": false },
  "settings": {
    "format": { "type": "select", "label": "Time format", "default": "24h", "options": [
      { "value": "24h", "label": "24-hour" }, { "value": "12h", "label": "12-hour" } ] },
    "color": { "type": "color", "label": "Text color", "default": "#FFFFFFFF" },
$themeSettings
  }
}
"@
$clockJs = @'
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
'@
New-Example -Name 'clock' -Manifest $clockManifest -Html $html -Css $css -Js $clockJs

$weatherManifest = @"
{
  "id": "com.rincew1nd.photoframe.weather",
  "name": "Weather",
  "version": "1.0.0",
  "apiVersion": 1,
  "minAppVersion": "1.0.0",
  "author": "Photo Frame",
  "license": "MIT",
  "description": "Current weather from the host weather service.",
  "entry": "index.html",
  "permissions": { "network": false },
  "inputs": ["weather", "config"],
  "placement": { "anchor": "top-end", "x": 0.70, "y": 0.06, "width": 230, "height": 96, "zOrder": 10, "showDuringNight": false },
  "settings": {
    "latitude": { "type": "number", "label": "Latitude", "default": 0, "min": -90, "max": 90, "step": 0.0001 },
    "longitude": { "type": "number", "label": "Longitude", "default": 0, "min": -180, "max": 180, "step": 0.0001 },
    "unit": { "type": "select", "label": "Unit", "default": "celsius", "options": [
      { "value": "celsius", "label": "Celsius" }, { "value": "fahrenheit", "label": "Fahrenheit" } ] },
    "locationLabel": { "type": "text", "label": "Location label", "default": "" },
$themeSettings
  }
}
"@
$weatherJs = @'
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
'@
New-Example -Name 'weather' -Manifest $weatherManifest -Html $html -Css $css -Js $weatherJs

$metadataManifest = @"
{
  "id": "com.rincew1nd.photoframe.metadata",
  "name": "Photo metadata",
  "version": "1.0.0",
  "apiVersion": 1,
  "minAppVersion": "1.0.0",
  "author": "Photo Frame",
  "license": "MIT",
  "description": "Current image description, date, location, and tags.",
  "entry": "index.html",
  "permissions": { "network": false },
  "inputs": ["image", "config"],
  "placement": { "anchor": "bottom-start", "x": 0.04, "y": 0.74, "width": 300, "height": 86, "zOrder": 10, "showDuringNight": false },
  "settings": {
    "showTags": { "type": "boolean", "label": "Show tags", "default": true },
$themeSettings
  }
}
"@
$metadataJs = @'
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
'@
New-Example -Name 'metadata' -Manifest $metadataManifest -Html $html -Css $css -Js $metadataJs

$calendarManifest = @"
{
  "id": "com.rincew1nd.photoframe.calendar",
  "name": "Calendar",
  "version": "1.0.0",
  "apiVersion": 1,
  "minAppVersion": "1.0.0",
  "author": "Photo Frame",
  "license": "MIT",
  "description": "Current date and weekday.",
  "entry": "index.html",
  "permissions": { "network": false },
  "inputs": ["time"],
  "placement": { "anchor": "top-start", "x": 0.04, "y": 0.30, "width": 220, "height": 88, "zOrder": 10, "showDuringNight": false },
  "settings": {
$themeSettings
  }
}
"@
$calendarJs = @'
function render(state) {
  const now = state && state.time ? new Date(state.time.epochMs) : new Date();
  document.getElementById('content').innerHTML =
    '<div class="value">' + now.toLocaleDateString(undefined, { weekday: 'long' }) +
    '</div><div class="body">' + now.toLocaleDateString() + '</div>';
}
host.getConfig().then(applyPluginTheme).catch(() => {});
host.onState(render);
host.getState().then(render).catch(() => render(null));
'@
New-Example -Name 'calendar' -Manifest $calendarManifest -Html $html -Css $css -Js $calendarJs

$playbackManifest = @"
{
  "id": "com.rincew1nd.photoframe.playback",
  "name": "Now playing",
  "version": "1.0.0",
  "apiVersion": 1,
  "minAppVersion": "1.0.0",
  "author": "Photo Frame",
  "license": "MIT",
  "description": "Background media title, artist, state, and playback controls.",
  "entry": "index.html",
  "permissions": { "network": false },
  "inputs": ["media", "config"],
  "actions": ["mediaPrevious", "mediaPlayPause", "mediaNext"],
  "placement": { "anchor": "bottom-end", "x": 0.70, "y": 0.66, "width": 240, "height": 160, "zOrder": 10, "showDuringNight": false },
  "settings": {
$themeSettings
  }
}
"@
$playbackJs = @'
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
'@
New-Example -Name 'playback' -Manifest $playbackManifest -Html $html -Css $css -Js $playbackJs

$imageInfoManifest = @"
{
  "id": "com.rincew1nd.photoframe.image-info",
  "name": "Image information",
  "version": "1.0.0",
  "apiVersion": 1,
  "minAppVersion": "1.0.0",
  "author": "Photo Frame",
  "license": "MIT",
  "description": "Dimensions, type, and cache status for the current image.",
  "entry": "index.html",
  "permissions": { "network": false },
  "inputs": ["image"],
  "placement": { "anchor": "center-end", "x": 0.72, "y": 0.40, "width": 240, "height": 96, "zOrder": 10, "showDuringNight": false },
  "settings": {
$themeSettings
  }
}
"@
$imageInfoJs = @'
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
'@
New-Example -Name 'image-info' -Manifest $imageInfoManifest -Html $html -Css $css -Js $imageInfoJs

Remove-Item -Recurse -Force $temp
Get-ChildItem $root -Filter *.zip | Select-Object Name, Length
