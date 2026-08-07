import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/supabase_service.dart';
import '../../utils/clipboard_paste.dart';
import '../../utils/error_message.dart';
import '../../utils/image_upload.dart';

/// หน้าสาธารณะสำหรับให้ช่างภายนอกส่งรูปอย่างเดียวโดยไม่ต้อง login
class ExternalWorkOrderUploadScreen extends StatefulWidget {
  final String token;

  const ExternalWorkOrderUploadScreen({
    super.key,
    required this.token,
  });

  @override
  State<ExternalWorkOrderUploadScreen> createState() =>
      _ExternalWorkOrderUploadScreenState();
}

class _ExternalWorkOrderUploadScreenState
    extends State<ExternalWorkOrderUploadScreen> {
  static const int _maxFileBytes = 10 * 1024 * 1024;
  static const int _maxNoteLength = 500;

  final _service = SupabaseService(Supabase.instance.client);
  final _picker = ImagePicker();
  final _noteController = TextEditingController();
  Map<String, dynamic>? _uploadContext;
  List<XFile> _selected = [];
  bool _loading = true;
  bool _uploading = false;
  String? _error;

  /// ตัวเลิกดัก paste event (no-op นอกเว็บ)
  late final void Function() _stopPasteListener;

  int get _uploadCount =>
      (_uploadContext?['upload_count'] as num?)?.toInt() ?? 0;
  int get _maxUploads =>
      (_uploadContext?['max_uploads'] as num?)?.toInt() ?? 20;
  int get _remaining =>
      (_maxUploads - _uploadCount).clamp(0, _maxUploads).toInt();

  @override
  void initState() {
    super.initState();
    _stopPasteListener = listenForPastedImages(
      _addImages,
      onRejected: () =>
          _showMessage('รูปที่วางมาเป็นชนิดที่ระบบไม่รองรับ (รับ jpg/png/webp)'),
    );
    _load();
  }

  @override
  void dispose() {
    _stopPasteListener();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final data = await _service.getExternalUploadContext(widget.token);
      if (mounted) {
        setState(() {
          _uploadContext = data;
          if (data == null) {
            _error = 'ลิงก์นี้ไม่ถูกต้อง หมดอายุ หรือใบงานถูกปิดแล้ว';
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// เพิ่มรูปเข้าคิว — ใช้ร่วมกันทั้งเลือกไฟล์ ถ่ายรูป และวางจากคลิปบอร์ด
  void _addImages(List<XFile> files) {
    // ระหว่างกำลังส่งอยู่ห้ามเพิ่ม ไม่งั้นรูปที่วางเข้ามาจะถูกล้างทิ้งพร้อมคิวเดิม
    if (!mounted || _uploading || files.isEmpty) return;
    final room = _remaining - _selected.length;
    if (room <= 0) {
      _showMessage('ส่งได้อีกสูงสุด $_remaining รูป');
      return;
    }
    final allowed = files.take(room).toList();
    setState(() => _selected = [..._selected, ...allowed]);
    if (files.length > allowed.length) {
      _showMessage('เพิ่มได้อีกสูงสุด $room รูป');
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final files = await pickUploadImages(_picker);
      _addImages(files);
    } catch (e) {
      _showMessage('เลือกรูปไม่สำเร็จ: ${friendlyError(e)}');
    }
  }

  Future<void> _takePhoto() async {
    try {
      final file = await pickUploadImage(_picker, ImageSource.camera);
      if (file != null) _addImages([file]);
    } catch (e) {
      _showMessage('เปิดกล้องไม่สำเร็จ: ${friendlyError(e)}');
    }
  }

  Future<void> _upload() async {
    if (_selected.isEmpty || _uploading) return;
    setState(() => _uploading = true);

    // ข้อความเดียวกันติดไปกับทุกรูปในรอบนี้ ผู้ดูแลจะได้เห็นว่ารูปชุดนี้คืออะไร
    final note = _noteController.text.trim();

    var uploaded = 0;
    try {
      for (final file in _selected) {
        final bytes = await file.readAsBytes();
        if (bytes.length > _maxFileBytes) {
          throw Exception('ไฟล์ ${file.name} มีขนาดเกิน 10 MB');
        }
        await _service.uploadExternalWorkOrderPhoto(
          widget.token,
          file.name,
          bytes,
          note: note.isEmpty ? null : note,
        );
        uploaded++;
      }
      _selected = [];
      _noteController.clear();
      await _load();
      _showMessage('ส่งรูปสำเร็จ $uploaded รูป', success: true);
    } catch (e) {
      await _load();
      _showMessage(
        uploaded > 0
            ? 'ส่งสำเร็จ $uploaded รูป แต่บางรูปส่งไม่สำเร็จ'
            : 'ส่งรูปไม่สำเร็จ: ${friendlyError(e)}',
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _showMessage(String message, {bool success = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? Colors.green : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ส่งรูปงาน')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _buildError()
                  : _buildUploader(),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.link_off, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildUploader() {
    final title = _uploadContext?['work_order_title'] as String? ?? '-';
    final property = _uploadContext?['property_name'] as String? ?? '-';

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Icon(Icons.add_a_photo_outlined, size: 56, color: Colors.teal),
        const SizedBox(height: 12),
        Text(
          'ส่งรูปให้ผู้ดูแลใบงาน',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        const Text(
          'หน้านี้ใช้ส่งรูปและข้อความเท่านั้น '
          'คุณไม่สามารถเปลี่ยนสถานะหรือแก้ไขใบงานได้',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.home_outlined, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(property)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'ส่งแล้ว $_uploadCount/$_maxUploads รูป',
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_remaining == 0)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 40),
                  SizedBox(height: 8),
                  Text('ส่งรูปครบจำนวนที่กำหนดแล้ว'),
                ],
              ),
            ),
          )
        else ...[
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _uploading ? null : _takePhoto,
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('ถ่ายรูป'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _uploading ? null : _pickFromGallery,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('เลือกรูป'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.content_paste_outlined, size: 16, color: Colors.grey),
              SizedBox(width: 6),
              Flexible(
                child: Text(
                  'ก๊อปรูปมาแล้วกด Ctrl+V (Mac: ⌘+V) วางตรงนี้ได้เลย',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _noteController,
            enabled: !_uploading,
            maxLines: 3,
            maxLength: _maxNoteLength,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(
              labelText: 'ข้อความถึงผู้ดูแล (ไม่บังคับ)',
              hintText: 'เช่น เปลี่ยนอะไหล่ตัวไหน เจอปัญหาอะไรเพิ่ม',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          if (_selected.isNotEmpty) ...[
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('พร้อมส่ง ${_selected.length} รูป'),
                    const SizedBox(height: 8),
                    for (final file in _selected)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            const Icon(Icons.image_outlined, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                file.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              onPressed: _uploading
                                  ? null
                                  : () => setState(
                                      () => _selected.remove(file),
                                    ),
                              icon: const Icon(Icons.close, size: 18),
                              tooltip: 'เอาออก',
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 50,
              child: FilledButton.icon(
                onPressed: _uploading ? null : _upload,
                icon: _uploading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.cloud_upload_outlined),
                label: Text(_uploading ? 'กำลังส่ง...' : 'ส่งรูป'),
              ),
            ),
          ],
        ],
      ],
    );
  }
}
