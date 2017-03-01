// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import 'package:json_object/json_object.dart';

typedef String HtmlBuilder(PageData data);

class AdminPage {
  final HtmlBuilder template;
  final dynamic postFormat;
  final Map<String, String> additional;

  AdminPage({this.template, this.postFormat, this.additional: const {}});
}

class PageData {
  final Map<String, String> constants;
  final additional = new Map<String, JsonObject>();
  dynamic request;
  JsonObject data;
  List<String> path;
  Map<String, Object> pathParameters;

  PageData(this.constants);
}

dynamic safe(Function fn, [dynamic fallback = null]) {
  try {
    return fn();
  } catch (e) {
    return fallback;
  }
}

String ucfirst(String str) => str[0].toUpperCase() + str.substring(1);

String prettyPrintErrorMessage(String message) {
  // Make quoted parts italics.
  final quotesRegex = new RegExp(r'"([^"]+)"');
  final msg = message.replaceAllMapped(
      quotesRegex, (match) => '<i>${match.group(1)}</i>');

  // Remove first part in pgpool messages.
  final pgpoolRegex = new RegExp(r'pgpool\d+:\d+:\d+\sERROR\s\d+\s(.*)');
  final match = pgpoolRegex.firstMatch(msg);
  if (match != null) {
    return ucfirst(match.group(1));
  } else {
    return ucfirst(msg);
  }
}
