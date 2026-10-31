const assert = require('node:assert/strict');
const { render } = require('../Resources/renderer.js');

assert.match(render('# Title\n\nHello **world**.'), /<h1 data-source-line="0">Title<\/h1>/);
assert.match(render('# Title\n\nHello **world**.'), /<strong>world<\/strong>/);
assert.match(render('| A | B |\n|---|---|\n| 1 | 2 |'), /<table/);
assert.match(render('~~old~~ and `code`'), /<s>old<\/s> and <code>code<\/code>/);
assert.match(render('```swift\nlet x = 1\n```'), /<pre data-source-line="0"><code class="language-swift">/);
assert.match(render('- first\n  - nested'), /<ul[\s\S]*<ul/);
assert.match(render('- [x] done\n- [ ] next'), /type="checkbox" disabled checked/);
assert.match(render('- [x] done\n- [ ] next'), /type="checkbox" disabled> next/);
assert.doesNotMatch(render('[x] plain paragraph'), /<input/);
assert.match(render('![local](images/photo.png)'), /src="images\/photo.png"/);
assert.match(render('[jump](#title)'), /href="#title"/);
assert.match(render('# नमस्ते 👋\n\n你好 café'), /नमस्ते 👋/);
assert.equal(render(''), '');
for (const payload of [
  '<script>alert(1)</script>',
  '<img src=x onerror=alert(1)>',
  '<iframe src="https://example.com"></iframe>',
  '[bad](javascript:alert(1))',
  '![bad](javascript:alert(1))',
  '[bad](data:text/html;base64,PHNjcmlwdD4=)',
]) {
  const output = render(payload);
  assert.doesNotMatch(output, /<script|<iframe|<img[^>]*onerror|(?:href|src)="(?:javascript:|data:text\/html)/i);
}
console.log('Renderer: formatting, tables, source mapping, Unicode, local links, and unsafe HTML checks passed.');
