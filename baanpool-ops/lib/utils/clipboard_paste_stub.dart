import 'package:image_picker/image_picker.dart';

/// นอกเว็บไม่มี paste event ให้ดัก — คืน no-op ไปเฉย ๆ
void Function() listenForPastedImages(
  void Function(List<XFile> images) onImages, {
  void Function()? onRejected,
}) {
  return () {};
}
