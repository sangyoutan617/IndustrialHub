import 'package:flutter/material.dart';
import '../../models/profile.dart';
import '../../services/profile_service.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/responsive_form_fields.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

enum _LoadState { loading, error, ready }

class _ProfileScreenState extends State<ProfileScreen> {
  final _profileService = ProfileService();
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _jobTitleController = TextEditingController();
  final _companyController = TextEditingController();

  _LoadState _state = _LoadState.loading;
  Profile? _profile;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _jobTitleController.dispose();
    _companyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);
    try {
      final profile = await _profileService.getMyProfile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _nameController.text = profile?.displayName ?? '';
        _phoneController.text = profile?.phone ?? '';
        _jobTitleController.text = profile?.jobTitle ?? '';
        _companyController.text = profile?.company ?? '';
        _state = _LoadState.ready;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _state = _LoadState.error);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      await _profileService.updateMyProfile(
        displayName: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        jobTitle: _jobTitleController.text.trim(),
        company: _companyController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile saved')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save profile. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My profile')),
      body: switch (_state) {
        _LoadState.loading => const LoadingIndicator(),
        _LoadState.error => ErrorState(
          message: 'Could not load your profile. Please try again.',
          onRetry: _load,
        ),
        _LoadState.ready => _buildForm(),
      },
    );
  }

  Widget _buildForm() {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            ResponsiveFormFields(
              children: [
                FormBreak(
                  Center(
                    child: CircleAvatar(
                      radius: 36,
                      backgroundColor: scheme.primaryContainer,
                      child: Icon(
                        Icons.person_outline,
                        size: 40,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                FormBreak(_readOnlyTile('Email', _profile?.email ?? '—', scheme)),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Full name'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _jobTitleController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Job title (e.g. Factory Manager)',
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _companyController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Company'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone'),
                ),
                const SizedBox(height: 24),
                FormBreak(
                  FilledButton(
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _readOnlyTile(String label, String value, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 15)),
        ],
      ),
    );
  }
}
