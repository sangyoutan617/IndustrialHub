import 'package:flutter/material.dart';
import '../../models/msic_code.dart';
import '../../services/capacity_service.dart';
import '../../services/factory_service.dart';
import '../../services/profile_service.dart';

/// Shown once, right after a new user's first sign-in (profiles.onboarded is
/// false). Collects their personal details and sets up their first factory,
/// then flips onboarded = true so it never shows again.
///
/// Everything except the two required names is optional, and there's a
/// "Skip for now" that just marks onboarding done — so a user is never
/// trapped here.
class OnboardingScreen extends StatefulWidget {
  /// Called once onboarding is finished (completed or skipped) so the gate
  /// above can swap in the home screen.
  final VoidCallback onComplete;

  const OnboardingScreen({super.key, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

// Malaysian states and federal territories, for the factory location.
const _malaysianStates = [
  'Johor',
  'Kedah',
  'Kelantan',
  'Melaka',
  'Negeri Sembilan',
  'Pahang',
  'Perak',
  'Perlis',
  'Pulau Pinang',
  'Sabah',
  'Sarawak',
  'Selangor',
  'Terengganu',
  'Wilayah Persekutuan Kuala Lumpur',
  'Wilayah Persekutuan Labuan',
  'Wilayah Persekutuan Putrajaya',
];

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _profileService = ProfileService();
  final _factoryService = FactoryService();
  final _capacityService = CapacityService();
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _jobTitleController = TextEditingController();
  final _companyController = TextEditingController();
  final _factoryNameController = TextEditingController();

  List<MsicCode> _msicCodes = [];
  String? _selectedMsic;
  String? _selectedState;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadMsic();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _jobTitleController.dispose();
    _companyController.dispose();
    _factoryNameController.dispose();
    super.dispose();
  }

  Future<void> _loadMsic() async {
    try {
      final codes = await _capacityService.getMsicCodes();
      if (mounted) setState(() => _msicCodes = codes);
    } catch (_) {
      // Industry is optional — leaving the dropdown empty is fine.
    }
  }

  Future<void> _finish() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      await _profileService.updateMyProfile(
        displayName: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        jobTitle: _jobTitleController.text.trim(),
        company: _companyController.text.trim(),
        onboarded: true,
      );
      await _factoryService.createFactory(
        _factoryNameController.text.trim(),
        state: _selectedState,
        msicCode: _selectedMsic,
      );
      widget.onComplete();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not finish setup. Please try again.'),
        ),
      );
    }
  }

  Future<void> _skip() async {
    setState(() => _isSubmitting = true);
    try {
      await _profileService.updateMyProfile(onboarded: true);
      widget.onComplete();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not continue. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 8),
              CircleAvatar(
                radius: 32,
                backgroundColor: scheme.primaryContainer,
                child: Icon(
                  Icons.waving_hand_outlined,
                  size: 32,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 16),
              Text('Welcome to Industrial Hub', style: textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                'Tell us a little about you and the factory you manage so we '
                'can set things up.',
                style: textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              _sectionLabel('About you', textTheme, scheme),
              const SizedBox(height: 12),
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
              const SizedBox(height: 28),
              _sectionLabel('Your factory', textTheme, scheme),
              const SizedBox(height: 12),
              TextFormField(
                controller: _factoryNameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Factory name'),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Factory name is required'
                    : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedMsic,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'What do you produce? (industry)',
                ),
                items: [
                  for (final code in _msicCodes)
                    DropdownMenuItem(
                      value: code.msicCode,
                      child: Text(
                        code.description,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _selectedMsic = v),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedState,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'State'),
                items: [
                  for (final state in _malaysianStates)
                    DropdownMenuItem(value: state, child: Text(state)),
                ],
                onChanged: (v) => setState(() => _selectedState = v),
              ),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: _isSubmitting ? null : _finish,
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Get started'),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _isSubmitting ? null : _skip,
                  child: const Text('Skip for now'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text, TextTheme textTheme, ColorScheme scheme) {
    return Text(
      text.toUpperCase(),
      style: textTheme.labelMedium?.copyWith(
        color: scheme.primary,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
      ),
    );
  }
}
