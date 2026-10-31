/* Slate's renderer. markdown-it 14.1.1 is vendored under its MIT license. */
(function (root) {
  'use strict';
  const factory = typeof module === 'object' && module.exports
    ? require('./vendor/markdown-it.min.js') : root.markdownit;
  const md = factory({ html: false, linkify: true, typographer: false, breaks: false });
  md.core.ruler.push('source_lines', function (state) {
    for (const token of state.tokens) {
      if (token.map && token.type !== 'inline' && token.type !== 'fence' && token.nesting !== -1) {
        token.attrSet('data-source-line', String(token.map[0]));
      }
    }
    for (let i = 2; i < state.tokens.length; i++) {
      const token = state.tokens[i];
      const item = state.tokens[i - 2];
      if (token.type !== 'inline' || item.type !== 'list_item_open' || !token.children?.length) continue;
      const first = token.children[0];
      const match = first.type === 'text' && first.content.match(/^\[([ xX])\]\s/);
      if (!match) continue;
      first.content = first.content.slice(match[0].length);
      const checkbox = new state.Token('html_inline', '', 0);
      checkbox.content = '<input type="checkbox" disabled' + (match[1].toLowerCase() === 'x' ? ' checked' : '') + '> ';
      token.children.unshift(checkbox);
      item.attrJoin('class', 'task-list-item');
    }
  });
  const originalFence = md.renderer.rules.fence;
  md.renderer.rules.fence = function (tokens, index, options, env, self) {
    const html = originalFence(tokens, index, options, env, self);
    return html.replace('<pre', '<pre data-source-line="' + tokens[index].map[0] + '"');
  };
  function render(source) {
    return md.render(source);
  }
  if (typeof module === 'object' && module.exports) module.exports = { render };
  else root.slateRender = render;
})(typeof window !== 'undefined' ? window : globalThis);
