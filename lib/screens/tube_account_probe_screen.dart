import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/tube_account_probe.dart';
import '../services/tube_session_service.dart';
import '../services/tube_storage_service.dart';

abstract class TubeProbeBrowser {
  Widget view();
  Future<void> open({
    required TubeProbeNavigation Function(String) navigation,
    required void Function(String) loaded,
    required VoidCallback failed,
  });
  Future<Map<String, String>> cookies();
  Future<String> userAgent();
  Future<void> returnToYouTube();
  Future<void> clear();
}

class _WebViewProbeBrowser implements TubeProbeBrowser {
  WebViewController? _controller;
  Future<void>? _opening;
  Future<void>? _clearing;
  @override
  Widget view() => _controller == null
      ? const Center(child: CircularProgressIndicator())
      : WebViewWidget(controller: _controller!);

  @override
  Future<void> open({
    required TubeProbeNavigation Function(String) navigation,
    required void Function(String) loaded,
    required VoidCallback failed,
  }) =>
      _opening = _open(navigation, loaded, failed);

  Future<void> _open(TubeProbeNavigation Function(String) navigation,
      void Function(String) loaded, VoidCallback failed) async {
    // Finish legacy retirement first so it cannot erase an in-progress sign-in.
    await TubeSessionService().init();
    // WebView's own cookie jar can survive process death. Mark before opening
    // so the next app startup clears an interrupted test as well.
    await const FlutterSecureStorage()
        .write(key: 'tube_account_probe_pending', value: 'true');
    await TubeSessionService.clearBrowserCookies();
    final controller = _controller = WebViewController();
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    // Keep the real WebView identity; no password/DOM interception or JS bridge.
    await controller.setNavigationDelegate(NavigationDelegate(
      onNavigationRequest: (request) {
        if (!request.isMainFrame) {
          return tubeProbeNavigation(request.url) ==
                  TubeProbeNavigation.rejected
              ? NavigationDecision.prevent
              : NavigationDecision.navigate;
        }
        return navigation(request.url) == TubeProbeNavigation.allow
            ? NavigationDecision.navigate
            : NavigationDecision.prevent;
      },
      onUrlChange: (change) {
        if (change.url != null) navigation(change.url!);
      },
      onPageFinished: loaded,
      onWebResourceError: (error) {
        if (error.isForMainFrame == true) failed();
      },
    ));
    await controller.loadRequest(Uri.parse(
        'https://accounts.google.com/ServiceLogin?service=youtube&continue=https%3A%2F%2Fwww.youtube.com%2F'));
  }

  @override
  Future<Map<String, String>> cookies() async => {
        for (final cookie in await WebViewCookieManager()
            .getCookies(domain: Uri.parse(TubeAccountProbe.origin)))
          cookie.name: cookie.value,
      };
  @override
  Future<String> userAgent() async => await _controller?.getUserAgent() ?? '';

  @override
  Future<void> returnToYouTube() async {
    await _controller?.loadRequest(Uri.parse(TubeAccountProbe.origin));
  }

  @override
  Future<void> clear() => _clearing ??= _clear().whenComplete(() {
        _clearing = null;
      });
  Future<void> _clear() async {
    try {
      await _opening;
    } catch (_) {
      // Startup can fail after touching the app-local browser store.
    }
    final controller = _controller;
    if (controller != null) {
      final blankLoaded = Completer<void>();
      await controller.setJavaScriptMode(JavaScriptMode.disabled);
      await controller.setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (r) => r.url == 'about:blank'
            ? NavigationDecision.navigate
            : NavigationDecision.prevent,
        onPageFinished: (url) {
          if (url == 'about:blank' && !blankLoaded.isCompleted) {
            blankLoaded.complete();
          }
        },
      ));
      await controller.loadRequest(Uri.parse('about:blank'));
      // Wait for the old sign-in document to stop before deleting its cookies.
      await blankLoaded.future.timeout(const Duration(seconds: 5));
      await controller.clearCache();
      await controller.clearLocalStorage();
    }
    await TubeSessionService.clearBrowserCookies();
    await const FlutterSecureStorage()
        .delete(key: 'tube_account_probe_pending');
  }
}

/// Verifies an app-local YouTube session, optionally saving the connection.
class TubeAccountProbeScreen extends StatefulWidget {
  const TubeAccountProbeScreen(
      {super.key,
      this.browserFactory,
      this.probe,
      this.saveConnection = false,
      this.session});
  final TubeProbeBrowser Function()? browserFactory;
  final TubeAccountProbe? probe;
  final bool saveConnection;
  final TubeSessionService? session;
  @override
  State<TubeAccountProbeScreen> createState() => _TubeAccountProbeScreenState();
}

class _TubeAccountProbeScreenState extends State<TubeAccountProbeScreen> {
  late final _probe = widget.probe ?? TubeAccountProbe();
  TubeProbeBrowser? _browser;
  TubeAccountProbeResult? _result;
  bool _starting = false;
  bool _checking = false;
  bool _closing = false;
  bool _canPop = false;
  bool _cleaned = false;
  bool _ready = false;
  bool _blocked = false;
  String _host = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    TubeStorageService().addListener(_privacyChanged);
  }

  void _privacyChanged() {
    if (TubeStorageService().isIncognito) unawaited(_finish());
  }

  TubeProbeNavigation _navigation(String url) {
    final decision = tubeProbeNavigation(url);
    if (mounted && !_closing) {
      setState(() {
        _ready = false;
        if (decision == TubeProbeNavigation.allow) {
          _host = Uri.parse(url).host;
        } else {
          _blocked = true;
          _error = decision == TubeProbeNavigation.rejected
              ? 'Google does not allow this embedded sign-in step. The test has stopped; no connection was saved.'
              : 'This sign-in step needs an unsupported destination (${tubeProbeDestinationLabel(url)}). The test has stopped; no connection was saved.';
        }
      });
    }
    if (_blocked) unawaited(_clearRejectedBrowser());
    return _blocked ? TubeProbeNavigation.rejected : decision;
  }

  Future<void> _clearRejectedBrowser() async {
    try {
      await _browser?.clear();
      _cleaned = true;
    } catch (_) {
      if (mounted && !_closing) {
        setState(() => _error =
            'Sign-in was stopped, but temporary browser cleanup did not finish. Tap Close test to retry cleanup.');
      }
    }
  }

  Future<void> _start() async {
    if (_starting || _closing || TubeStorageService().isIncognito) return;
    setState(() {
      _starting = true;
      _error = null;
      _browser = (widget.browserFactory ?? _WebViewProbeBrowser.new)();
    });
    try {
      await _browser!.open(
        navigation: _navigation,
        loaded: (url) {
          final uri = Uri.tryParse(url);
          if (mounted && !_closing && !_blocked) {
            setState(() {
              _host = tubeProbeNavigation(url) == TubeProbeNavigation.allow
                  ? uri!.host
                  : '';
              _ready = {'youtube.com', 'www.youtube.com', 'm.youtube.com'}
                  .contains(_host);
            });
          }
        },
        failed: () {
          if (mounted && !_closing) {
            setState(() {
              _ready = false;
              _error =
                  'The sign-in page could not load. Close the test and try again when your connection is available.';
            });
          }
        },
      );
    } catch (_) {
      if (mounted && !_closing) {
        setState(() => _error =
            'The sign-in browser is unavailable. No account connection was saved.');
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _returnToYouTube() async {
    if (_starting || _checking || _closing || _blocked) return;
    setState(() {
      _starting = true;
      _ready = false;
      _error = null;
    });
    try {
      await _browser!.returnToYouTube();
    } catch (_) {
      if (mounted && !_closing) {
        setState(() => _error =
            'YouTube could not open. Check your connection or close the test.');
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _check() async {
    if (!_ready || _blocked || _checking || _closing) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    Map<String, String>? cookies;
    try {
      cookies = await _browser!.cookies();
      final userAgent = await _browser!.userAgent();
      final result = await _probe.check(cookies,
          userAgent: userAgent,
          stillActive: () => mounted && !_closing && !_blocked);
      if (!mounted || _closing || _blocked) return;
      // Clear the browser jar before optionally saving the verified credentials
      // in encrypted storage. The diagnostic-only route never saves them.
      await _browser!.clear();
      _cleaned = true;
      if (widget.saveConnection) {
        if (!mounted || _closing) return;
        final saved = await (widget.session ?? TubeSessionService())
            .savePrivateConnection(cookies,
                name: result.name,
                userAgent: userAgent,
                avatar: result.avatar,
                handle: result.handle,
                stillActive: () => mounted && !_closing && !_blocked);
        if (saved && mounted && !_closing) {
          setState(() => _canPop = true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.pop(context, true);
          });
        } else if (mounted && !_closing) {
          setState(() => _error =
              'The connection changed before it could be saved. Close this window and reconnect.');
        }
        return;
      }
      if (mounted && !_closing) setState(() => _result = result);
    } on TubeAccountProbeException catch (e) {
      if (mounted && !_closing) setState(() => _error = e.message);
      if (e.reason == TubeAccountProbeFailure.rejected) {
        _blocked = true;
        _ready = false;
        await _clearRejectedBrowser();
      }
    } catch (_) {
      if (mounted && !_closing) {
        setState(() => _error =
            'The test could not finish. Close the test to remove its temporary sign-in data.');
      }
    } finally {
      cookies?.clear();
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _finish() async {
    if (_closing) return;
    setState(() => _closing = true);
    try {
      if (!_cleaned) await _browser?.clear();
      _cleaned = true;
      if (!mounted) return;
      setState(() => _canPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _closing = false;
          _error =
              'Temporary browser cleanup did not finish. Tap Close test again to retry.';
        });
      }
    }
  }

  @override
  void dispose() {
    TubeStorageService().removeListener(_privacyChanged);
    _probe.close();
    if (!_cleaned) {
      unawaited(_browser?.clear().catchError((Object _) {}));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: _canPop,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(_finish());
        },
        child: Scaffold(
          appBar: AppBar(
              title: Text(widget.saveConnection
                  ? 'Connect personalized feed'
                  : 'YouTube connection test'),
              leading: IconButton(
                  tooltip: widget.saveConnection
                      ? 'Cancel connection'
                      : 'Close test',
                  onPressed: _closing ? null : _finish,
                  icon: const Icon(Icons.close))),
          body: SafeArea(
              child: Column(children: [
            if (_browser == null)
              Expanded(
                  child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(children: [
                        Text(widget.saveConnection
                            ? 'Sign in to YouTube in this separate window, then tap Finish connecting. This does not reuse Chrome’s login. You enter your details on Google’s website; ShreyX has no password form.\n\nYour verified session is encrypted on this device and sent only to YouTube. It stays connected after you close or restart ShreyX, until you disconnect or YouTube expires it. Home and Up Next use YouTube’s returned recommendations. Guest preferences and local history are preserved. Incognito uses Guest requests.\n\nThis is experimental and uses private YouTube endpoints. Identical rankings and complete synchronization are not guaranteed. Watching in ShreyX does not write back to your YouTube history.'
                            : 'Test whether YouTube allows a separate sign-in for ShreyX Tube. This does not reuse Chrome’s login. You enter your details on Google’s website; ShreyX has no password form.\n\nAfter signing in, tap Check sign-in to request a native preview of your account’s recommendations. For this check, ShreyX uses session cookies from this sign-in window only and sends them directly to YouTube. The temporary session is cleared when the test finishes or you close it. Your existing feed is not changed.\n\nThis is experimental. Google may refuse this browser, and identical recommendations or full synchronization are not guaranteed.'),
                        const SizedBox(height: 24),
                        FilledButton(
                            onPressed: _starting ||
                                    _closing ||
                                    TubeStorageService().isIncognito
                                ? null
                                : _start,
                            child: Text(widget.saveConnection
                                ? 'Sign in and connect feed'
                                : 'Start sign-in test')),
                        if (TubeStorageService().isIncognito)
                          const Text('Leave Incognito to test an account.'),
                      ]))),
            if (_browser != null && _result == null) ...[
              Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(_host.isEmpty
                      ? 'Opening a separate sign-in session…'
                      : 'Website: $_host')),
              if (_starting || _checking) const LinearProgressIndicator(),
              if (_error == null)
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(widget.saveConnection
                        ? 'Finish sign-in yourself, then tap Finish connecting to save this connection on your phone.'
                        : 'Finish sign-in yourself. Then check the connection; no account is saved by this test.')),
              FilledButton(
                  onPressed: _ready &&
                          !_starting &&
                          !_checking &&
                          !_closing &&
                          !_blocked
                      ? _check
                      : null,
                  child: Text(_checking
                      ? 'Checking account and feed…'
                      : widget.saveConnection
                          ? 'Finish connecting'
                          : 'Check sign-in and preview feed')),
              if (_host == 'myaccount.google.com' && !_blocked) ...[
                const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                        'If Google has finished signing in, return to YouTube to check the connection.')),
                OutlinedButton(
                    onPressed: _starting || _checking || _closing
                        ? null
                        : _returnToYouTube,
                    child: const Text('Return to YouTube')),
              ],
              if (!_blocked) Expanded(child: _browser!.view()),
            ],
            if (_result != null) ...[
              Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                      'Account verified: ${_result!.name}\n${_result!.videos.length} native video previews returned. Temporary sign-in data has been cleared.')),
              const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                      'These are YouTube’s returned regular-video recommendations in their original order. Shorts and ad cards are excluded. This proves only the connection test; native Home is still unchanged.')),
              if (_result!.videos.isEmpty)
                const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                        'Sign-in was verified, but YouTube returned no supported video cards. A personalized native feed has not been demonstrated.')),
              Expanded(
                  child: ListView.builder(
                      itemCount: _result!.videos.length,
                      itemBuilder: (_, i) => ListTile(
                          leading: Text('${i + 1}'),
                          title: Text(_result!.videos[i].title),
                          subtitle: Text(_result!.videos[i].channelTitle)))),
            ],
            if (_error != null)
              Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error))),
            TextButton(
                onPressed: _closing ? null : _finish,
                child: Text(_closing
                    ? 'Clearing sign-in data…'
                    : widget.saveConnection
                        ? 'Cancel connection'
                        : 'Close test')),
          ])),
        ),
      );
}
