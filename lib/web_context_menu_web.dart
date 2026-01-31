// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

void disableWebContextMenu() {
  html.document.onContextMenu.listen((event) {
    event.preventDefault();
  });
}
