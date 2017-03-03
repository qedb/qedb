// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

library eqpg.htgen;

import 'dart:mirrors';

@proxy
class ElementBuilder {
  final String tag, prepend;
  final bool selfClosing;

  ElementBuilder(this.tag, this.prepend, this.selfClosing);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final pArgs = invocation.positionalArguments;

    final classes = new List<String>();
    List children = [];
    var id = '';
    var text = '';

    // Figure out classes and IDs.
    var parsedIdClasses = false;
    for (final arg in pArgs) {
      if (arg is List) {
        children = arg;
      } else if (arg is String) {
        if (!parsedIdClasses) {
          // Try to parse first argument as class or ID.
          var str = arg;
          final idPattern = new RegExp(r'#([0-9a-z-]+)(?:.|$)');
          final classPattern = new RegExp(r'\.([0-9a-z-]+)(?:\.|$)');
          final idMatch = idPattern.matchAsPrefix(str);
          if (idMatch != null) {
            id = idMatch.group(1);
            str = str.substring(id.length + 1);
          }

          // Parse classes.
          while (str.isNotEmpty) {
            final classMatch = classPattern.matchAsPrefix(str);

            if (classMatch == null) {
              id = '';
              classes.clear();
              text = str;
              parsedIdClasses = true;
              break;
            } else {
              classes.add(classMatch.group(1));
              str = str.substring(classes.last.length + 1);
            }
          }

          parsedIdClasses = true;
        } else {
          text = arg;
        }
      }
    }

    // Convert named parameters to String -> String map.
    final named = invocation.namedArguments;
    final attrs = new Map<String, String>.fromIterable(named.keys,
        key: (sym) => MirrorSystem.getName(sym).replaceAll('_', ''),
        value: (sym) => named[sym].toString());

    // Add parsed ID and classes to attributes.
    if (id.isNotEmpty) {
      attrs['id'] = id;
    }
    if (classes.isNotEmpty) {
      attrs['class'] = classes.join(' ');
    }

    // Remove children attribute.
    attrs.remove('c');

    // Generate attribute string.
    final akeys = attrs.keys.toList();
    final attrsStr = new List<String>.generate(
        akeys.length, (i) => '${akeys[i]}="${attrs[akeys[i]]}"').join(' ');

    // Assign named parameter child list to children.
    if (named.containsKey(#c)) {
      children = new List.from(named[#c]);
    }

    // Process children (that is, collapse lists into each other).
    var containedLists = true;
    while (containedLists) {
      containedLists = false;
      for (var i = 0; i < children.length; i++) {
        if (children[i] is List) {
          containedLists = true;
          final list = children.removeAt(i);

          // Insert all items of this list at this position,
          // and move the index forward.
          children.insertAll(i, list);
          i += list.length - 1;
        }
      }
    }

    final open = akeys.isEmpty ? tag : '$tag $attrsStr';
    if (children.isNotEmpty) {
      return '$prepend<$open>${children.join()}</$tag>';
    } else if (text.isNotEmpty) {
      return '$prepend<$open>$text</$tag>';
    } else {
      return selfClosing ? '$prepend<$open>' : '$prepend<$open></$open>';
    }
  }
}

/// Helper for writing style attributes.
String buildStyle(Map<String, dynamic> props) {
  final k = props.keys.toList();
  return new List<String>.generate(
      k.length, (i) => '${k[i]}:${props[k[i]].toString()};').join();
}

// Some element builders for regular elements.
// Yeah, this is pure pollution of the global namespace.

dynamic _getElementBuilder(String tag,
        {String prepend = '', bool selfClosing: false}) =>
    new ElementBuilder(tag, prepend, selfClosing);

final a = _getElementBuilder('a');
final body = _getElementBuilder('body');
final br = _getElementBuilder('br', selfClosing: true);
final button = _getElementBuilder('button');
final code = _getElementBuilder('code');
final div = _getElementBuilder('div');
final form = _getElementBuilder('form');
final h1 = _getElementBuilder('h1');
final h2 = _getElementBuilder('h2');
final h3 = _getElementBuilder('h3');
final h4 = _getElementBuilder('h4');
final h5 = _getElementBuilder('h5');
final h6 = _getElementBuilder('h6');
final head = _getElementBuilder('head');
final html = _getElementBuilder('html', prepend: '<!DOCTYPE html>');
final img = _getElementBuilder('img', selfClosing: true);
final input = _getElementBuilder('input', selfClosing: true);
final label = _getElementBuilder('label');
final li = _getElementBuilder('li');
final link = _getElementBuilder('link');
final meta = _getElementBuilder('meta');
final nav = _getElementBuilder('nav');
final ol = _getElementBuilder('ol');
final option = _getElementBuilder('option');
final p = _getElementBuilder('p');
final script = _getElementBuilder('script');
final select = _getElementBuilder('select');
final small = _getElementBuilder('small');
final span = _getElementBuilder('span');
final style = _getElementBuilder('style');
final svg = _getElementBuilder('svg');
final table = _getElementBuilder('table');
final tbody = _getElementBuilder('tbody');
final td = _getElementBuilder('td');
final th = _getElementBuilder('th');
final thead = _getElementBuilder('thead');
final title = _getElementBuilder('title');
final tr = _getElementBuilder('tr');
final ul = _getElementBuilder('ul');
