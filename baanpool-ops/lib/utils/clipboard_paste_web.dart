/// Implementation ฝั่งเว็บของ [listenForPastedImages]
///
/// ใช้ `dart:js_interop` ตรง ๆ แทนการเพิ่ม package ใหม่ เพราะต้องการแค่
/// `document.addEventListener('paste', ...)` กับการอ่าน bytes ออกจากไฟล์
///
/// ดักที่ document (ไม่ใช่ที่ TextField) เพราะ paste event จะ bubble ขึ้นมา
/// เสมอ ไม่ว่าตอนนั้นเคอร์เซอร์จะอยู่ในช่องพิมพ์ข้อความหรือไม่
library;

import 'dart:js_interop';

import 'package:image_picker/image_picker.dart';

import 'clipboard_paste.dart' show pastedImageName;

@JS('document')
external _Document get _document;

extension type _Document._(JSObject _) implements JSObject {
  external void addEventListener(String type, JSFunction listener);
  external void removeEventListener(String type, JSFunction listener);
}

extension type _ClipboardEvent._(JSObject _) implements JSObject {
  external _DataTransfer? get clipboardData;
}

extension type _DataTransfer._(JSObject _) implements JSObject {
  external _FileList? get files;
}

extension type _FileList._(JSObject _) implements JSObject {
  external int get length;
  external _File? item(int index);
}

extension type _File._(JSObject _) implements JSObject {
  external String get type;
  external JSPromise<JSArrayBuffer> arrayBuffer();
}

void Function() listenForPastedImages(
  void Function(List<XFile> images) onImages, {
  void Function()? onRejected,
}) {
  Future<void> handle(_ClipboardEvent event) async {
    final files = event.clipboardData?.files;
    if (files == null || files.length == 0) return;

    final images = <XFile>[];
    var rejected = false;
    for (var i = 0; i < files.length; i++) {
      final file = files.item(i);
      if (file == null) continue;
      final mimeType = file.type;
      if (!mimeType.startsWith('image/')) continue;

      final name = pastedImageName(mimeType);
      if (name == null) {
        rejected = true;
        continue;
      }
      final buffer = await file.arrayBuffer().toDart;
      final bytes = buffer.toDart.asUint8List();
      images.add(
        XFile.fromData(
          bytes,
          name: name,
          mimeType: mimeType,
          length: bytes.length,
        ),
      );
    }

    if (images.isNotEmpty) {
      onImages(images);
    } else if (rejected) {
      onRejected?.call();
    }
  }

  // เก็บ reference ของ JSFunction ตัวเดียวไว้ ไม่งั้น removeEventListener
  // จะถอด listener ไม่ออก (`.toJS` สร้าง object ใหม่ทุกครั้งที่เรียก)
  final listener = ((JSObject event) {
    handle(event as _ClipboardEvent);
  }).toJS;

  _document.addEventListener('paste', listener);
  return () => _document.removeEventListener('paste', listener);
}
