// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import 'package:json_object/json_object.dart';

typedef String HtmlBuilder(PageSessionData s);
typedef dynamic PostDataBuilder(Map<String, String> formData);

/// Page information
class Page {
  final HtmlBuilder template;
  final PostDataBuilder onPost;
  final Map<String, String> additional;

  Page({this.template, this.onPost, this.additional: const {}});
}

/// Page session data
class PageSessionData {
  final Map<String, String> settings;
  final Map<String, String> snippets;
  final Map<String, dynamic> additional;
  final Set<String> allRoutes;

  dynamic request;
  dynamic response;

  List<String> path;
  Map<String, Object> pathParameters;

  PageSessionData(this.settings, this.snippets, this.allRoutes)
      : additional = new Map<String, JsonObject>() {
    request = new JsonObject();
    response = new JsonObject();
  }

  String relativeUrl(String route) {
    final base = new List<String>.from(path);
    base.removeLast();
    final baseUrl = base.join('/');
    return '/$baseUrl/$route';
  }
}

/// Convert given JSON data into a JsonObject, or if its not a Map, fallback to
/// Dart object.
dynamic jsonify(dynamic data) {
  if (data is Map) {
    return new JsonObject.fromMap(data);
  } else if (data is Iterable) {
    return new List.generate(data.length, (i) => jsonify(data.elementAt(i)));
  } else {
    return data;
  }
}

/// Returns return value of [fn], or [fallback] if [fn] errors.
dynamic safe(Function fn, [dynamic fallback = null]) {
  try {
    return fn();
  } catch (e) {
    return fallback;
  }
}

/// Convert first character in the string to upper case.
String ucfirst(String str) => str[0].toUpperCase() + str.substring(1);

/// Pretty print error messages for alert box.
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
