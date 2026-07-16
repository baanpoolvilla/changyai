import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/user.dart';
import '../../services/auth_state_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/error_message.dart';

/// Roles Management Screen — Admin can view all users and change their roles
class RolesManagementScreen extends StatefulWidget {
  const RolesManagementScreen({super.key});

  @override
  State<RolesManagementScreen> createState() => _RolesManagementScreenState();
}

class _RolesManagementScreenState extends State<RolesManagementScreen> {
  final _svc = SupabaseService(Supabase.instance.client);
  List<AppUser> _users = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await _svc.getUsers();
      setState(() {
        _users = data.map((json) => AppUser.fromJson(json)).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'โหลดข้อมูลผู้ใช้ไม่สำเร็จ: ${friendlyError(e)}';
        _loading = false;
      });
    }
  }

  Future<void> _changeRole(AppUser user, UserRole newRole) async {
    try {
      await _svc.updateUserRole(user.id, newRole.name);

      // Refresh the user's profile if it's the current user
      if (user.id == Supabase.instance.client.auth.currentUser?.id) {
        await AuthStateService().loadUserProfile();
      }

      await _loadUsers();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'เปลี่ยน role ของ ${user.fullName} เป็น ${newRole.displayName} แล้ว',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เปลี่ยน role ไม่สำเร็จ: ${friendlyError(e)}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showRenameDialog(AppUser user) {
    final nameCtrl = TextEditingController(text: user.fullName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('เปลี่ยนชื่อ'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(labelText: 'ชื่อ-นามสกุล'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () async {
              final newName = nameCtrl.text.trim();
              if (newName.isEmpty) return;
              Navigator.pop(context);
              try {
                await _svc.updateUser(user.id, {'full_name': newName});
                await _loadUsers();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('เปลี่ยนชื่อเป็น $newName แล้ว'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('เปลี่ยนชื่อไม่สำเร็จ: ${friendlyError(e)}'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmDialog(AppUser user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ลบผู้ใช้'),
        content: Text(
          'ต้องการลบ "${user.fullName}" ออกจากระบบหรือไม่?\n\nการดำเนินการนี้ไม่สามารถย้อนกลับได้',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(context);
              try {
                await _svc.deleteUser(user.id);
                await _loadUsers();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('ลบ ${user.fullName} แล้ว'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('ลบไม่สำเร็จ: ${friendlyError(e)}'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('ลบ'),
          ),
        ],
      ),
    );
  }

  void _showChangeRoleDialog(AppUser user) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('เปลี่ยน Role: ${user.fullName}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'ปัจจุบัน: ${user.role.displayName}',
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              ...UserRole.values.map((role) {
                final isCurrentRole = role == user.role;
                return ListTile(
                  leading: Icon(
                    _getRoleIcon(role),
                    color: isCurrentRole
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  title: Text(role.displayName),
                  subtitle: Text(_getRoleDescription(role)),
                  selected: isCurrentRole,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  onTap: isCurrentRole
                      ? null
                      : () {
                          Navigator.pop(context);
                          _changeRole(user, role);
                        },
                );
              }),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ยกเลิก'),
            ),
          ],
        );
      },
    );
  }

  void _showAddUserDialog() {
    final emailController = TextEditingController();
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    UserRole selectedRole = UserRole.technician;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('เพิ่มผู้ใช้ใหม่'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'ชื่อ-นามสกุล *',
                          prefixIcon: Icon(Icons.person),
                        ),
                        validator: (v) =>
                            v == null || v.isEmpty ? 'กรุณากรอกชื่อ' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'อีเมล *',
                          prefixIcon: Icon(Icons.email),
                        ),
                        validator: (v) =>
                            v == null || v.isEmpty ? 'กรุณากรอกอีเมล' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'เบอร์โทร',
                          prefixIcon: Icon(Icons.phone),
                        ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<UserRole>(
                        value: selectedRole,
                        decoration: const InputDecoration(
                          labelText: 'Role',
                          prefixIcon: Icon(Icons.badge),
                        ),
                        items: UserRole.values.map((role) {
                          return DropdownMenuItem(
                            value: role,
                            child: Text(role.displayName),
                          );
                        }).toList(),
                        onChanged: (v) {
                          if (v != null) {
                            setDialogState(() => selectedRole = v);
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'ผู้ใช้สามารถเข้าสู่ระบบผ่าน LINE ได้ทันที\nไม่จำเป็นต้องตั้งรหัสผ่าน',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('ยกเลิก'),
                ),
                FilledButton(
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;

                    Navigator.pop(context);

                    try {
                      await _svc.createUser(
                        fullName: nameController.text.trim(),
                        email: emailController.text.trim(),
                        role: selectedRole.name,
                        phone: phoneController.text.trim().isEmpty
                            ? null
                            : phoneController.text.trim(),
                      );

                      await _loadUsers();

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('สร้างผู้ใช้ใหม่สำเร็จ'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('สร้างผู้ใช้ไม่สำเร็จ: ${friendlyError(e)}'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('สร้าง'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  IconData _getRoleIcon(UserRole role) {
    switch (role) {
      case UserRole.admin:
        return Icons.admin_panel_settings;
      case UserRole.owner:
        return Icons.star;
      case UserRole.manager:
        return Icons.manage_accounts;
      case UserRole.caretaker:
        return Icons.home_work;
      case UserRole.technician:
        return Icons.engineering;
    }
  }

  String _getRoleDescription(UserRole role) {
    switch (role) {
      case UserRole.admin:
        return 'เข้าถึงทุกส่วนของระบบ จัดการผู้ใช้ได้';
      case UserRole.owner:
        return 'เจ้าของ เข้าถึงทุกส่วนได้';
      case UserRole.manager:
        return 'ผู้จัดการ มอบหมายผู้ดูแลบ้านและช่างได้';
      case UserRole.caretaker:
        return 'ผู้ดูแลบ้าน มอบหมายช่างได้';
      case UserRole.technician:
        return 'เห็นเฉพาะงานที่ได้รับมอบหมาย';
    }
  }

  Color _getRoleColor(UserRole role) {
    switch (role) {
      case UserRole.admin:
        return Colors.purple;
      case UserRole.owner:
        return Colors.amber.shade700;
      case UserRole.manager:
        return Colors.blue;
      case UserRole.caretaker:
        return Colors.green;
      case UserRole.technician:
        return Colors.teal;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('จัดการ Roles'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadUsers,
            tooltip: 'รีเฟรช',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddUserDialog,
        icon: const Icon(Icons.person_add),
        label: const Text('เพิ่มผู้ใช้'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _loadUsers,
                    child: const Text('ลองใหม่'),
                  ),
                ],
              ),
            )
          : _users.isEmpty
          ? const Center(child: Text('ยังไม่มีผู้ใช้ในระบบ'))
          : RefreshIndicator(
              onRefresh: _loadUsers,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _users.length,
                itemBuilder: (context, index) {
                  final user = _users[index];
                  final isCurrentUser =
                      user.id == Supabase.instance.client.auth.currentUser?.id;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: _getRoleColor(
                          user.role,
                        ).withOpacity(0.2),
                        child: Icon(
                          _getRoleIcon(user.role),
                          color: _getRoleColor(user.role),
                        ),
                      ),
                      title: Row(
                        children: [
                          Flexible(child: Text(user.fullName)),
                          if (isCurrentUser) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'คุณ',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(user.email),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _getRoleColor(user.role).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              user.role.displayName,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _getRoleColor(user.role),
                              ),
                            ),
                          ),
                        ],
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          switch (value) {
                            case 'role':
                              _showChangeRoleDialog(user);
                              break;
                            case 'rename':
                              _showRenameDialog(user);
                              break;
                            case 'delete':
                              if (!isCurrentUser) {
                                _showDeleteConfirmDialog(user);
                              }
                              break;
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'role',
                            child: ListTile(
                              leading: Icon(Icons.swap_horiz),
                              title: Text('เปลี่ยน Role'),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'rename',
                            child: ListTile(
                              leading: Icon(Icons.edit),
                              title: Text('เปลี่ยนชื่อ'),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          if (!isCurrentUser)
                            const PopupMenuItem(
                              value: 'delete',
                              child: ListTile(
                                leading: Icon(Icons.delete, color: Colors.red),
                                title: Text(
                                  'ลบผู้ใช้',
                                  style: TextStyle(color: Colors.red),
                                ),
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                        ],
                      ),
                      isThreeLine: true,
                    ),
                  );
                },
              ),
            ),
    );
  }
}
