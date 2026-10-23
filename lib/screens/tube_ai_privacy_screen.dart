import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/tube_intelligence_store.dart';
import '../services/tube_storage_service.dart';
import '../services/tube_database_service.dart';
import '../widgets/tube_intelligence_theme.dart';

class TubeAiPrivacyScreen extends StatefulWidget {
  const TubeAiPrivacyScreen({super.key, this.store});
  final TubeIntelligenceStore? store;
  @override
  State<TubeAiPrivacyScreen> createState() => _TubeAiPrivacyScreenState();
}

class _TubeAiPrivacyScreenState extends State<TubeAiPrivacyScreen> {
  late final store = widget.store ?? TubeIntelligenceStore();
  final _url = TextEditingController(), _token = TextEditingController();
  bool _allowed = false, _busy = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await store.init();
      if (!mounted) return;
      _url.text = store.endpoint;
      _token.text = store.accessToken;
      setState(() {
        _allowed = store.externalAllowed;
        _busy = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              'Could not read AI settings. Retry by reopening this screen.';
          _busy = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await store.configure(
        allowed: _allowed,
        url: _url.text,
        token: _token.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AI privacy choices saved.')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is FormatException
              ? e.message.toString()
              : 'Could not save AI settings. Retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear(bool history) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          history ? 'Clear viewing history?' : 'Clear study materials?',
        ),
        content: Text(
          history
              ? 'Delete locally saved viewing history. Existing playback can record new history unless history is paused.'
              : 'Delete all saved video responses and notes, and cancel active analysis. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (history) {
        await TubeStorageService().clearWatchHistory();
        await TubeDatabaseService().clearWatchHistory();
      } else {
        await store.clearMaterials();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              history
                  ? 'Viewing history deleted.'
                  : 'Saved study materials deleted.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Deletion did not complete. Retry.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      TubeIntelligenceTheme(builder: _buildContent);

  Widget _buildContent(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text(
            'AI privacy',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Local by default',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Local analysis searches and extracts from your transcript on this device. It is not a live generative AI result. Importing pasted text and using the labelled demo send no transcript to an AI service. Loading captions contacts YouTube.',
            ),
            const SizedBox(height: 12),
            const Text(
              'External AI sends the selected transcript, video ID, title and current question to your configured gateway and Google Gemini only when you explicitly run it. Your YouTube cookies, account tokens and viewing history are not included. The gateway should not retain content; its operator and Google still process the request.',
            ),
            const SizedBox(height: 12),
            const Text(
              'Google’s unpaid Gemini services may use input and output to improve products, and human reviewers may process content. Do not send sensitive, personal or confidential text. Regional eligibility, quotas and prices vary; a free tier is not unlimited.',
            ),
            const SizedBox(height: 12),
            SelectableText(
              'Provider terms: https://ai.google.dev/gemini-api/terms\nPricing and quotas: https://ai.google.dev/gemini-api/docs/pricing',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Allow external AI processing'),
              subtitle: const Text(
                'Off by default. Incognito always disables external processing and saving.',
              ),
              value: _allowed,
              onChanged: _busy ? null : (v) => setState(() => _allowed = v),
            ),
            TextField(
              controller: _url,
              enabled: !_busy,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'AI gateway HTTPS origin',
                hintText: 'https://your-gateway.example',
                helperText:
                    'Use your deployed gateway, not the Google API URL.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _token,
              enabled: !_busy,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              autofillHints: const [],
              inputFormatters: [LengthLimitingTextInputFormatter(512)],
              decoration: const InputDecoration(
                labelText: 'Your gateway access token',
                helperText:
                    'Stored with Android encryption. Never enter a provider API key.',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: const Text('Save AI privacy choices'),
            ),
            if (_error != null)
              Semantics(
                liveRegion: true,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              ),
            const Divider(height: 32),
            const Text(
              'Saved data',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const Text(
              'Responses and notes are saved locally only after you choose Save materials. Unsaved conversations and transcripts remain in memory while the workbench is open. Saved excerpts can contain transcript content. No transcript is automatically uploaded for analysis.',
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _busy ? null : () => _clear(false),
              child: const Text('Clear saved responses and notes'),
            ),
            OutlinedButton(
              onPressed: _busy ? null : () => _clear(true),
              child: const Text('Clear viewing history'),
            ),
          ],
        ),
      );
}
