// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import 'dart:html';

T _createElement<T extends Element>(
    T createdElement, String classes, List<Element> c, void store(T element)) {
  final classNames = classes.split('.')..removeWhere((str) => str.isEmpty);
  createdElement.classes.addAll(classNames);
  c.where((c) => c != null).forEach((child) => createdElement.append(child));

  if (store != null) {
    store(createdElement);
  }
  return createdElement;
}

DivElement div(String classes,
        {List<Element> c: const [], void store(DivElement element)}) =>
    _createElement<DivElement>(new DivElement(), classes, c, store);

SpanElement span(String classes,
        {List<Element> c: const [], void store(SpanElement element)}) =>
    _createElement<SpanElement>(new SpanElement(), classes, c, store);

SpanElement checkbox(String label, void callback(bool checked)) {
  final toggle = (Element target) => callback(target.classes.toggle('checked'));
  return span('.checkbox')
    ..text = label
    ..tabIndex = 0
    ..onKeyDown.listen((e) {
      if (e.keyCode == KeyCode.ENTER || e.keyCode == KeyCode.SPACE) {
        toggle(e.target);
        e.preventDefault();
      }
    })
    ..onClick.listen((e) => toggle(e.target));
}
