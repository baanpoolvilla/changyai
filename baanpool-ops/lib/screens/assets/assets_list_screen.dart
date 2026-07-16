import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/asset.dart';
import '../../services/supabase_service.dart';
import '../../utils/error_message.dart';

class AssetsListScreen extends StatefulWidget {
  const AssetsListScreen({super.key});

  @override
  State<AssetsListScreen> createState() => _AssetsListScreenState();
}

class _AssetsListScreenState extends State<AssetsListScreen> {
  final _service = SupabaseService(Supabase.instance.client);
  List<Asset> _assets = [];
  Map<String, DateTime?> _lastMaintenanceDates = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _service.getAssets();
      _assets = data.map((e) => Asset.fromJson(e)).toList();

      // Load last maintenance dates
      if (_assets.isNotEmpty) {
        _lastMaintenanceDates = await _service.getLastMaintenanceDates(
          _assets.map((a) => a.id).toList(),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('โหลดข้อมูลล้มเหลว: ${friendlyError(e)}')));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('อุปกรณ์ทั้งหมด')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _assets.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.devices_other,
                    size: 64,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  const Text('ยังไม่มีข้อมูลอุปกรณ์'),
                  const SizedBox(height: 8),
                  const Text(
                    'เพิ่มอุปกรณ์ได้ที่หน้ารายละเอียดบ้าน',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _assets.length,
                itemBuilder: (context, index) {
                  final a = _assets[index];
                  final lastMaint = _lastMaintenanceDates[a.id];
                  final lastMaintText = lastMaint != null
                      ? '🔧 ล่าสุด: ${lastMaint.day}/${lastMaint.month}/${lastMaint.year}'
                      : '🔧 ยังไม่เคย maintenance';
                  return Card(
                    child: ListTile(
                      leading: a.imageUrl != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                a.imageUrl!,
                                width: 48,
                                height: 48,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    const CircleAvatar(
                                      child: Icon(Icons.build),
                                    ),
                              ),
                            )
                          : const CircleAvatar(child: Icon(Icons.build)),
                      title: Text(a.name),
                      subtitle: Text(lastMaintText),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await context.push('/assets/${a.id}');
                        _load();
                      },
                    ),
                  );
                },
              ),
            ),
    );
  }
}
