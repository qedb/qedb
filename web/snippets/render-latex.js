// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

var spans = document.getElementsByClassName('latex')
for (var i = 0; i < spans.length; i++) {
  var span = spans[i]
  var latex = span.innerText
  latex = latex.replace(/\$([0-9]+)/g, function (match, p1) {
    return '\\textsf{\\$}' + p1
  })
  katex.render(latex, span, {displayMode: true})
}
