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
