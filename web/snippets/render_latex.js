// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

var subopchars = {
  '=': '{=}',
  '^': '\\hat{}',
  '~': '{\\sim}'
};

var spans = document.getElementsByClassName('latex')
for (var i = 0; i < spans.length; i++) {
  var span = spans[i]
  var latex = span.innerText
  latex = latex.replace(/(\$(?:(\d+)|\(([^\d]?)(\d+)([^\d]?)\)))/g, function (_, g1) {
    var fixed = g1.replace(/([=^~])/g, function(_, g1) { return subopchars[g1]; });
    return '\\mathsf{\\' + fixed + '}'
  })
  katex.render(latex, span, {displayMode: true})
}
