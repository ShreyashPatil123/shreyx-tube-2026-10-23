import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../services/tube_session_service.dart';
import '../services/tube_youtube_account_client.dart';
import 'tube_account_probe_screen.dart';

const tubeConnectExplanation =
    'Choose your own Google account using Google’s account chooser and consent flow. ShreyX Tube requests read-only access to your channel and subscriptions. This official connection does not read passwords or browser cookies. Account metadata is encrypted on this device; short-lived access tokens stay in memory and go only to Google’s official YouTube API. Home, Shorts and recommendations continue using the existing Guest discovery. Google’s API does not expose your personalized Home or watch history. Incognito uses Guest requests.';

class TubeAuthScreen extends StatefulWidget {
  const TubeAuthScreen({super.key});
  @override
  State<TubeAuthScreen> createState() => _TubeAuthScreenState();
}

class _TubeAuthScreenState extends State<TubeAuthScreen> {
  bool _busy = false;
  String? _error;
  Future<void> _connectFeed() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final connected = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  const TubeAccountProbeScreen(saveConnection: true)));
      if (connected == true && mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await TubeSessionService().connect();
      if (mounted && TubeSessionService().isLoggedIn) {
        Navigator.pop(context, true);
      }
    } on TubeAccountApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on GoogleSignInException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.code == GoogleSignInExceptionCode.canceled
          ? 'Sign-in was cancelled. If this happened after selecting an account, the app’s Google registration may need checking.'
          : 'Google sign-in could not complete. Check your connection or try again.');
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Account connection could not complete. Check the app’s Google registration, YouTube API access and your connection. Guest Mode is still available.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openBrowser() async {
    try {
      final opened =
          await const MethodChannel('com.shreyx.tube/session_browser')
              .invokeMethod<bool>('openBrowser');
      if (opened != true && mounted) {
        setState(() => _error = 'No supported browser is available.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Your default browser could not open.');
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_busy,
        child: Scaffold(
          appBar: AppBar(
              title: const Text('Connect YouTube Account'),
              leading: IconButton(
                  tooltip: 'Close sign-in',
                  onPressed: _busy ? null : () => Navigator.pop(context, false),
                  icon: const Icon(Icons.close))),
          body: SafeArea(
              child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        OutlinedButton.icon(
                            onPressed: _busy ? null : _connectFeed,
                            icon: const Icon(Icons.video_library_outlined),
                            label: const Text(
                                'Connect personalized YouTube feed')),
                        const SizedBox(height: 8),
                        const Text(
                            'Experimental native recommendations with a session saved only on this device. Sign in once; reconnect if YouTube expires it.'),
                        const Divider(height: 32),
                        const Text('Official Google connection'),
                        const Icon(Icons.account_circle_outlined, size: 48),
                        const SizedBox(height: 20),
                        const Text(tubeConnectExplanation),
                        const SizedBox(height: 24),
                        if (!TubeSessionService().isConfigured) ...[
                          const Text(
                              'Official Google API connection is not enabled in this build yet. You can keep using Guest Mode.'),
                          const SizedBox(height: 16),
                        ],
                        if (_error != null)
                          Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text(_error!,
                                  style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error))),
                        FilledButton.icon(
                            onPressed:
                                _busy || !TubeSessionService().isConfigured
                                    ? null
                                    : _connect,
                            icon: const Icon(Icons.login),
                            label: Text(_busy
                                ? 'Connecting…'
                                : 'Continue with Google')),
                        if (_busy)
                          const Padding(
                              padding: EdgeInsets.all(16),
                              child:
                                  Center(child: CircularProgressIndicator())),
                        TextButton(
                            onPressed: _busy
                                ? null
                                : () => Navigator.pop(context, false),
                            child: const Text('Continue as Guest')),
                        const Divider(height: 40),
                        OutlinedButton.icon(
                            onPressed: _busy
                                ? null
                                : () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            const TubeAccountProbeScreen())),
                            icon: const Icon(Icons.science_outlined),
                            label: const Text(
                                'Test personalized YouTube connection')),
                        const SizedBox(height: 8),
                        const Text(
                            'Experimental separate sign-in and native feed preview. This test does not save an account connection.'),
                        const Divider(height: 40),
                        OutlinedButton.icon(
                            onPressed: _busy ? null : _openBrowser,
                            icon: const Icon(Icons.open_in_browser),
                            label:
                                const Text('Open YouTube in default browser')),
                        const SizedBox(height: 8),
                        const Text(
                            'Uses your browser’s existing sign-in. Opening YouTube there does not connect ShreyX Tube.'),
                      ]))),
        ),
      );
}
