import 'package:flutter/material.dart';
import '../services/tube_device_setup_service.dart';

class TubeDeviceSetupScreen extends StatefulWidget {
  const TubeDeviceSetupScreen({super.key, this.initialSetup = false});
  final bool initialSetup;
  @override
  State<TubeDeviceSetupScreen> createState() => _TubeDeviceSetupScreenState();
}

class _TubeDeviceSetupScreenState extends State<TubeDeviceSetupScreen>
    with WidgetsBindingObserver {
  TubeDeviceSetupStatus? _status;
  bool _busy = false;
  String? _error;
  int _request = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final request = ++_request;
    final status = await TubeDeviceSetupService.inspect();
    if (mounted && request == _request) setState(() => _status = status);
  }

  Future<void> _action(String action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final opened = await TubeDeviceSetupService.action(action);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!opened) {
        _error =
            'Could not open the Android permission or settings screen. Try again.';
      }
    });
    await _refresh();
  }

  Future<void> _continue() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await TubeDeviceSetupService().complete();
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not save setup. Try again.';
        });
      }
    }
  }

  Widget _card(IconData icon, String title, String detail, String button,
          String action,
          {bool enabled = true}) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(icon),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w600)))
            ]),
            const SizedBox(height: 8),
            Text(detail),
            const SizedBox(height: 12),
            OutlinedButton(
                onPressed: _busy || !enabled ? null : () => _action(action),
                child: Text(button)),
          ]),
        ),
      );
  @override
  Widget build(BuildContext context) {
    final status = _status;
    return Scaffold(
      appBar: AppBar(
          title: const Text('Permissions & link setup'),
          automaticallyImplyLeading: !widget.initialSetup),
      body: SafeArea(
          child: Center(
              child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('Set up ShreyX Tube',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
              'Review these choices before you start. You can continue without enabling them and change them later in Privacy & Local Data.'),
          const SizedBox(height: 12),
          if (_error != null)
            Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))),
          if (status == null)
            const Center(child: CircularProgressIndicator())
          else if (!status.available) ...[
            const Text('Android settings could not be checked.'),
            TextButton(onPressed: _refresh, child: const Text('Check again')),
          ] else ...[
            _card(
                Icons.link,
                'Open YouTube links in ShreyX',
                status.linksReady
                    ? 'Supported links are enabled. Links delivered here ask whether to play in ShreyX Tube or open YouTube.'
                    : status.linksSupported
                        ? '${status.selectedDomains} of ${status.domains.length} link domains enabled. In Android settings, choose In the app (or enable Open supported links), then add/select the YouTube and youtu.be addresses.'
                        : 'Choose ShreyX Tube in Android’s Open with menu. Clear YouTube’s defaults if Android opens it automatically.',
                'Set up supported links',
                'openLinkSettings'),
            if (status.youtubeInstalled)
              _card(
                  Icons.open_in_new,
                  'If links still open YouTube',
                  'Open YouTube’s defaults and choose In your browser, turn off Open supported links, or clear defaults. Return here and enable ShreyX’s supported addresses. Some apps explicitly open YouTube; use Share → ShreyX Tube in those apps.',
                  'YouTube link defaults',
                  'openYouTubeSettings'),
            if (status.youtubeMusicInstalled &&
                status.domains['music.youtube.com'] == 'disabled')
              _card(
                  Icons.music_note,
                  'YouTube Music links',
                  'YouTube Music may hold music.youtube.com links. Choose In your browser or turn off Open supported links in its defaults, then add that address to ShreyX.',
                  'YouTube Music link defaults',
                  'openYouTubeMusicSettings'),
            _card(
                Icons.notifications_outlined,
                'Playback notifications',
                status.notificationsEnabled
                    ? 'Notifications are enabled.'
                    : 'Allow playback notifications to keep playback controls accessible outside the app.',
                status.notificationsEnabled
                    ? 'Notifications enabled'
                    : status.canRequestNotifications
                        ? 'Allow notifications'
                        : 'Notification settings',
                status.canRequestNotifications
                    ? 'requestNotifications'
                    : 'openNotificationSettings',
                enabled: !status.notificationsEnabled),
            if (status.pipSupported)
              _card(
                  Icons.picture_in_picture_alt,
                  'Picture-in-picture',
                  status.pipEnabled
                      ? 'Allowed. Keep watching in a floating window when you leave the app.'
                      : 'Allow picture-in-picture to keep the video visible when you leave the app.',
                  status.pipEnabled
                      ? 'Picture-in-picture allowed'
                      : 'Allow picture-in-picture',
                  'openPipSettings',
                  enabled: !status.pipEnabled),
          ],
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                  'Internet and background playback access are provided by Android without a permission prompt. Downloads stay in app-private storage, so no photo or storage access is needed.')),
          if (widget.initialSetup)
            FilledButton(
                onPressed: _busy ? null : _continue,
                child: Text(status?.linksReady == true
                    ? 'Continue'
                    : 'Continue for now')),
        ]),
      ))),
    );
  }
}
