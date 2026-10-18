import 'package:engine_core/engine_core.dart';
import 'package:flutter/material.dart';

import 'bootstrapper.dart';

/// The bootstrap / updates window (design §2.13): what the release server offers, what
/// each item would change, and a choice per item. Nothing is downloaded until an item is
/// accepted and Install is pressed. A server that cannot be reached, or a manifest that fails
/// its signature check, is said plainly, and the studio keeps working with what is cached.
class BootstrapScreen extends StatefulWidget {
  const BootstrapScreen({super.key, required this.bootstrapper});

  final Bootstrapper bootstrapper;

  @override
  State<BootstrapScreen> createState() => _BootstrapScreenState();
}

class _BootstrapScreenState extends State<BootstrapScreen> {
  BootstrapPlan? _plan;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _plan = null;
    });
    final plan = await widget.bootstrapper.check();
    if (mounted) setState(() => _plan = plan);
  }

  Future<void> _install() async {
    final plan = _plan;
    if (plan == null || _busy) return;
    setState(() => _busy = true);
    await widget.bootstrapper.installAccepted(
      plan.items,
      onChanged: () {
        if (mounted) setState(() {});
      },
    );
    if (mounted) setState(() => _busy = false);
  }

  static String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String _why(ManifestRejection? r) => switch (r) {
    ManifestRejection.unsigned => 'The release list is not signed.',
    ManifestRejection.invalidSignature =>
      'The release list\'s signature does not match the publisher\'s key.',
    ManifestRejection.checksumMismatch =>
      'A download does not match its checksum.',
    null => 'The release list could not be verified.',
  };

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Updates and downloads'),
        actions: [
          IconButton(
            key: const Key('bootstrap-refresh'),
            tooltip: 'Check again',
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: plan == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (plan.problem == PlanProblem.offline)
                  MaterialBanner(
                    key: const Key('bootstrap-offline'),
                    content: Text(
                      'The release server cannot be reached (${plan.detail}). '
                      'Existing projects still open, using what is already downloaded.',
                    ),
                    actions: [
                      TextButton(
                        key: const Key('bootstrap-retry-check'),
                        onPressed: _refresh,
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                if (plan.problem == PlanProblem.rejected)
                  MaterialBanner(
                    key: const Key('bootstrap-rejected'),
                    content: Text(
                      'Nothing was offered. ${_why(plan.rejection)}',
                    ),
                    actions: const [SizedBox.shrink()],
                  ),
                if (plan.problem == PlanProblem.none && plan.items.isEmpty)
                  const Expanded(
                    child: Center(
                      child: Text(
                        'Nothing to download.',
                        key: Key('bootstrap-empty'),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView(
                      children: [for (final item in plan.items) _row(item)],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      key: const Key('bootstrap-install'),
                      onPressed:
                          _busy ||
                              !plan.items.any(
                                (i) =>
                                    i.decision == Decision.accept &&
                                    i.status != InstallStatus.installed,
                              )
                          ? null
                          : _install,
                      child: const Text('Install accepted'),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _row(BootstrapItem bi) {
    final name = bi.item.name;
    final stateLabel = switch (bi.state) {
      ItemState.missing => 'New',
      ItemState.updateAvailable => 'Update',
      ItemState.current => 'Up to date',
    };
    final status = switch (bi.status) {
      InstallStatus.installed => 'Installed, checksum verified',
      InstallStatus.downloading =>
        'Downloading ${(bi.progress * 100).round()}%',
      InstallStatus.failed => 'Failed: ${bi.error}',
      InstallStatus.notStarted => null,
    };
    return ListTile(
      key: Key('bootstrap-item-$name'),
      title: Text(name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$stateLabel · ${_size(bi.item.size)}'),
          if (status != null) Text(status, key: Key('bootstrap-status-$name')),
          if (bi.status == InstallStatus.downloading)
            LinearProgressIndicator(value: bi.progress),
        ],
      ),
      trailing: bi.state == ItemState.current
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (bi.status == InstallStatus.failed)
                  TextButton(
                    key: Key('bootstrap-retry-$name'),
                    onPressed: _busy ? null : _install,
                    child: const Text('Retry'),
                  ),
                SegmentedButton<Decision>(
                  key: Key('bootstrap-decision-$name'),
                  showSelectedIcon: false,
                  emptySelectionAllowed: true,
                  segments: const [
                    ButtonSegment(
                      value: Decision.accept,
                      label: Text('Accept'),
                    ),
                    ButtonSegment(value: Decision.defer, label: Text('Later')),
                    ButtonSegment(value: Decision.skip, label: Text('Skip')),
                  ],
                  selected: {if (bi.decision != Decision.pending) bi.decision},
                  onSelectionChanged:
                      _busy || bi.status == InstallStatus.installed
                      ? null
                      : (s) {
                          if (s.isEmpty) return;
                          final choice = s.first;
                          if (choice == Decision.skip) {
                            widget.bootstrapper.skip(bi);
                          } else {
                            bi.decision = choice;
                          }
                          setState(() {});
                        },
                ),
              ],
            ),
    );
  }
}
