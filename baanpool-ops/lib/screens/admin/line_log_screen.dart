import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LineLogScreen extends StatefulWidget {
  const LineLogScreen({super.key});

  @override
  State<LineLogScreen> createState() => _LineLogScreenState();
}

class _LineLogScreenState extends State<LineLogScreen> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _client
          .from('line_notification_logs')
          .select()
          .order('sent_at', ascending: false)
          .limit(300);
      setState(() {
        _logs = List<Map<String, dynamic>>.from(data);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'โหลดข้อมูลไม่สำเร็จ: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Log การส่ง LINE'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'รีเฟรช',
            onPressed: _loadLogs,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            TextButton(onPressed: _loadLogs, child: const Text('ลองใหม่')),
          ],
        ),
      );
    }

    if (_logs.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'ยังไม่มีประวัติการส่ง LINE',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadLogs,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Text(
                  'แสดง ${_logs.length} รายการล่าสุด',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              itemCount: _logs.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) => _buildLogTile(_logs[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogTile(Map<String, dynamic> log) {
    final sentAt = DateTime.tryParse(log['sent_at'] as String? ?? '');
    final recipientName =
        (log['recipient_name'] as String?)?.isNotEmpty == true
            ? log['recipient_name'] as String
            : log['recipient_line_user_id'] as String? ?? '-';
    final messagePreview = log['message_preview'] as String? ?? '';
    final isFlex = (log['message_type'] as String?) == 'flex';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor:
            isFlex ? Colors.green.shade50 : Colors.blue.shade50,
        child: Icon(
          isFlex ? Icons.dashboard_customize_outlined : Icons.message_outlined,
          color: isFlex ? Colors.green.shade600 : Colors.blue.shade600,
          size: 20,
        ),
      ),
      title: Text(
        recipientName,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (messagePreview.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                messagePreview.replaceAll('\n', ' '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
            ),
          if (sentAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                DateFormat('dd/MM/yyyy HH:mm').format(sentAt.toLocal()),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ),
        ],
      ),
      isThreeLine: messagePreview.isNotEmpty,
      trailing: isFlex
          ? Chip(
              label: const Text('Flex', style: TextStyle(fontSize: 11)),
              padding: EdgeInsets.zero,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              backgroundColor: Colors.green.shade50,
              side: BorderSide(color: Colors.green.shade200),
            )
          : null,
      onTap: () => _showDetail(context, log),
    );
  }

  void _showDetail(BuildContext context, Map<String, dynamic> log) {
    final sentAt = DateTime.tryParse(log['sent_at'] as String? ?? '');
    final recipientName = log['recipient_name'] as String? ?? '-';
    final lineUserId = log['recipient_line_user_id'] as String? ?? '-';
    final messagePreview = log['message_preview'] as String? ?? '-';
    final isFlex = (log['message_type'] as String?) == 'flex';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              isFlex
                  ? Icons.dashboard_customize_outlined
                  : Icons.message_outlined,
              size: 20,
              color: isFlex ? Colors.green : Colors.blue,
            ),
            const SizedBox(width: 8),
            const Text('รายละเอียดการส่ง LINE'),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _row('ผู้รับ', recipientName),
              _row('LINE ID', lineUserId),
              _row('ประเภท', isFlex ? 'Flex Message' : 'ข้อความธรรมดา'),
              if (sentAt != null)
                _row(
                  'เวลาส่ง',
                  DateFormat('dd/MM/yyyy HH:mm:ss').format(sentAt.toLocal()),
                ),
              const SizedBox(height: 12),
              const Text(
                'ข้อความ:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  messagePreview,
                  style: const TextStyle(fontSize: 13, height: 1.5),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ปิด'),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              '$label:',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
