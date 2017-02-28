// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

typedef String HtmlBuilder(PageData data);

class AdminPage {
  final HtmlBuilder template;
  final dynamic postFormat;
  AdminPage({this.template, this.postFormat});
}

class PageData {
  Map<String, String> constants;
  Map<String, dynamic> additional;
  dynamic request;
  dynamic data;
  List<String> path;
  Map<String, Object> pathParameters;

  PageData(this.constants);
}
