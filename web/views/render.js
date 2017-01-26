// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

var fs = require('fs')
var pug = require('pug')
var process = require('process')
var readline = require('readline');

var fileName = process.argv[2]
fs.readFile(fileName, (err, buf) => {
  if (err) {
    throw err;
  }
  var str = buf.toString('utf8');
  var fn = pug.compile(str);

  // Start listening on stdin.
  var lineReader = readline.createInterface({
    input: process.openStdin()
  });
  lineReader.on('line', function (line) {
    var json = JSON.parse(line);
    process.stdout.write(fn(json));
  });
});
