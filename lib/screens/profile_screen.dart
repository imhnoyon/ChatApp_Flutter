import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/models.dart';
import '../services/api_service.dart';

class ProfileScreen extends StatefulWidget {
  final VoidCallback? onProfileUpdated;

  const ProfileScreen({super.key, this.onProfileUpdated});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _api = ApiService();
  final _auth = AuthService();
  final _usernamCtrl = TextEditingController();

  late User _user;
  File? _newAvatarFile;
  bool _loading = false;
  bool _saving = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _user = _auth.me ?? User(id: 0, username: 'User');
    _usernamCtrl.text = _user.username;
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      await _api.fetchMe();
      if (mounted) {
        _user = _auth.me ?? _user;
        _usernamCtrl.text = _user.username;
        setState(() => _loading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMsg = e.toString());
        _showError(_errorMsg ?? 'Failed to load profile');
      }
    }
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() => _newAvatarFile = File(image.path));
    }
  }

// Local URL resolver removed in favor of ApiService.resolveMediaUrl

  Future<void> _saveProfile() async {
    final newUsername = _usernamCtrl.text.trim();

    // Validation
    if (newUsername.isEmpty) {
      _showError('Username cannot be empty');
      return;
    }

    if (newUsername.length < 3) {
      _showError('Username must be at least 3 characters');
      return;
    }

    if (!mounted) return;
    setState(() => _saving = true);

    try {
      List<int>? avatarBytes;
      String? avatarFilename;

      if (_newAvatarFile != null) {
        avatarBytes = await _newAvatarFile!.readAsBytes();
        avatarFilename = _newAvatarFile!.path.split('/').last;
      }

      await _api.updateProfile(
          username: newUsername,
          avatarBytes: avatarBytes,
          avatarFilename: avatarFilename);

      await _api.fetchMe();

      if (mounted) {
        setState(() {
          _saving = false;
          _newAvatarFile = null;
          _user = _auth.me ?? _user;
        });
        _showSuccess('Profile updated successfully!');
        widget.onProfileUpdated?.call();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _showError(e.toString());
      }
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.green.shade700,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    _usernamCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Avatar Section
            Center(
              child: Stack(
                children: [
                  // Display avatar
                  GestureDetector(
                    onTap: _pickAvatar,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: theme.colorScheme.primary,
                          width: 2,
                        ),
                      ),
                      child: _newAvatarFile != null
                          ? CircleAvatar(
                              radius: 60,
                              backgroundImage: FileImage(_newAvatarFile!),
                            )
                          : (_api.resolveMediaUrl(_user.avatar).isNotEmpty
                              ? CircleAvatar(
                                  radius: 60,
                                  backgroundImage: CachedNetworkImageProvider(
                                      _api.resolveMediaUrl(_user.avatar)),
                                )
                              : CircleAvatar(
                                  radius: 60,
                                  backgroundColor:
                                      theme.colorScheme.primary.withValues(
                                    alpha: 0.3,
                                  ),
                                  child: Text(
                                    _user.initials,
                                    style: const TextStyle(fontSize: 28),
                                  ),
                                )),
                    ),
                  ),
                  // Camera icon
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.colorScheme.primary,
                      ),
                      padding: const EdgeInsets.all(8),
                      child: GestureDetector(
                        onTap: _pickAvatar,
                        child: const Icon(
                          Icons.camera_alt,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // User Info Display
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'User ID: ${_user.id}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Email: ${_user.email ?? 'N/A'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Edit Form
            Form(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Edit Profile',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 12),

                  // Username Field
                  TextField(
                    controller: _usernamCtrl,
                    enabled: !_saving,
                    decoration: InputDecoration(
                      labelText: 'Username',
                      hintText: 'Enter your username',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      prefixIcon: const Icon(Icons.person),
                      errorText: _errorMsg,
                    ),
                    onChanged: (_) {
                      setState(() => _errorMsg = null);
                    },
                  ),
                  const SizedBox(height: 16),

                  // Avatar Status
                  if (_newAvatarFile != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle,
                              color: Colors.blue.shade700, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Avatar selected: ${_newAvatarFile!.path.split('/').last}',
                            style: TextStyle(
                              color: Colors.blue.shade700,
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 24),

                  // Save Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _saving ? null : _saveProfile,
                      icon: _saving
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Theme.of(context).colorScheme.onPrimary,
                                ),
                              ),
                            )
                          : const Icon(Icons.save),
                      label: Text(_saving ? 'Saving...' : 'Save Changes'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Help Text
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info, color: Colors.amber.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tap the avatar to upload a new profile picture',
                      style: TextStyle(
                        color: Colors.amber.shade700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
