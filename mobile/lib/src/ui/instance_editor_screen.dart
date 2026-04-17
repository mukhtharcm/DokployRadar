import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_models.dart';
import '../models/dokploy_models.dart';
import '../services/dashboard_controller.dart';

enum _ConnectionBannerState {
  idle,
  testing,
  success,
  failure,
}

class InstanceEditorScreen extends StatefulWidget {
  const InstanceEditorScreen({
    super.key,
    this.instance,
  });

  final DokployInstance? instance;

  bool get isEditing => instance != null;

  @override
  State<InstanceEditorScreen> createState() => _InstanceEditorScreenState();
}

class _InstanceEditorScreenState extends State<InstanceEditorScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _apiTokenController;

  _ConnectionBannerState _connectionState = _ConnectionBannerState.idle;
  DokployConnectionSummary? _connectionSummary;
  String? _connectionError;
  bool _isEnabled = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.instance?.name ?? '');
    _baseUrlController = TextEditingController(text: widget.instance?.baseUrlString ?? '');
    _apiTokenController = TextEditingController(text: widget.instance?.apiToken ?? '');
    _isEnabled = widget.instance?.isEnabled ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _baseUrlController.dispose();
    _apiTokenController.dispose();
    super.dispose();
  }

  bool get _canSave {
    return _nameController.text.trim().isNotEmpty &&
        _baseUrlController.text.trim().isNotEmpty &&
        _apiTokenController.text.trim().isNotEmpty &&
        !_isSaving;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit instance' : 'Add instance'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Text(
              widget.isEditing
                  ? 'Update the Dokploy instance connection used by the mobile app.'
                  : 'Add a Dokploy URL and API token to start monitoring deployments.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Instance name',
                hintText: 'Production',
              ),
              textInputAction: TextInputAction.next,
              onChanged: (_) => _resetConnectionState(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _baseUrlController,
              decoration: const InputDecoration(
                labelText: 'Base URL',
                hintText: 'https://dokploy.example.com',
              ),
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
              onChanged: (_) => _resetConnectionState(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _apiTokenController,
              decoration: const InputDecoration(
                labelText: 'API token',
                hintText: 'Paste your Dokploy API token',
              ),
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              onChanged: (_) => _resetConnectionState(),
            ),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _isEnabled,
              title: const Text('Enable monitoring immediately'),
              subtitle: const Text('Disabled instances stay saved but won’t be polled.'),
              onChanged: (value) {
                setState(() => _isEnabled = value);
              },
            ),
            const SizedBox(height: 8),
            Text(
              'Dokploy Radar reads your inventory and deployment history through the public Dokploy API using this token.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (_connectionState != _ConnectionBannerState.idle) ...[
              const SizedBox(height: 20),
              _ConnectionBanner(
                state: _connectionState,
                summary: _connectionSummary,
                errorMessage: _connectionError,
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _canSave ? _testConnection : null,
                    icon: _connectionState == _ConnectionBannerState.testing
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.wifi_find_rounded),
                    label: const Text('Test connection'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _canSave ? _save : null,
                    icon: _isSaving
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_rounded),
                    label: Text(widget.isEditing ? 'Save changes' : 'Save instance'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _testConnection() async {
    final controller = context.read<DashboardController>();

    setState(() {
      _connectionState = _ConnectionBannerState.testing;
      _connectionSummary = null;
      _connectionError = null;
    });

    try {
      final summary = await controller.testConnection(
        name: _nameController.text,
        baseUrlString: _baseUrlController.text,
        apiToken: _apiTokenController.text,
        existingId: widget.instance?.id,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _connectionState = _ConnectionBannerState.success;
        _connectionSummary = summary;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _connectionState = _ConnectionBannerState.failure;
        _connectionError = error.toString();
      });
    }
  }

  Future<void> _save() async {
    final controller = context.read<DashboardController>();

    setState(() => _isSaving = true);

    try {
      await controller.saveInstance(
        name: _nameController.text,
        baseUrlString: _baseUrlController.text,
        apiToken: _apiTokenController.text,
        editingId: widget.instance?.id,
        isEnabled: _isEnabled,
      );

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
      setState(() => _isSaving = false);
    }
  }

  void _resetConnectionState() {
    if (_connectionState == _ConnectionBannerState.idle) {
      return;
    }

    setState(() {
      _connectionState = _ConnectionBannerState.idle;
      _connectionSummary = null;
      _connectionError = null;
    });
  }
}

class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({
    required this.state,
    required this.summary,
    required this.errorMessage,
  });

  final _ConnectionBannerState state;
  final DokployConnectionSummary? summary;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final color = switch (state) {
      _ConnectionBannerState.testing => scheme.primary,
      _ConnectionBannerState.success => Colors.green.shade600,
      _ConnectionBannerState.failure => scheme.error,
      _ConnectionBannerState.idle => scheme.secondary,
    };

    final title = switch (state) {
      _ConnectionBannerState.testing => 'Testing connection…',
      _ConnectionBannerState.success => 'Connection successful',
      _ConnectionBannerState.failure => 'Connection failed',
      _ConnectionBannerState.idle => '',
    };

    final message = switch (state) {
      _ConnectionBannerState.testing => 'Dokploy Radar is checking the host, token, and deployment APIs.',
      _ConnectionBannerState.success =>
        'Connected to ${summary?.projectCount ?? 0} project(s) • ${summary?.serviceCount ?? 0} services • ${summary?.deployingCount ?? 0} deploying • ${summary?.failedCount ?? 0} failed',
      _ConnectionBannerState.failure => errorMessage ?? 'Unknown error.',
      _ConnectionBannerState.idle => '',
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            switch (state) {
              _ConnectionBannerState.testing => Icons.sync_rounded,
              _ConnectionBannerState.success => Icons.check_circle_rounded,
              _ConnectionBannerState.failure => Icons.error_rounded,
              _ConnectionBannerState.idle => Icons.info_rounded,
            },
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 4),
                Text(message),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
