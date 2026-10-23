import 'package:flutter/material.dart';
import '../models/tube_models.dart';
import '../services/tube_search_service.dart';
import '../services/tube_user_profile_service.dart';
import '../services/tube_session_service.dart';
import 'tube_auth_screen.dart';

class TubeOnboardingScreen extends StatefulWidget {
  final bool editing;
  const TubeOnboardingScreen({super.key, this.editing = false});
  @override
  State<TubeOnboardingScreen> createState() => _TubeOnboardingScreenState();
}

class _TubeOnboardingScreenState extends State<TubeOnboardingScreen> {
  final _form = GlobalKey<FormState>();
  final _profile = TubeUserProfileService();
  late final TextEditingController _name;
  late final TextEditingController _handle;
  final _creatorQuery = TextEditingController();
  final _topic = TextEditingController();
  late Set<String> _types;
  late Set<String> _interests;
  late Map<String, TubeChannelInfo> _creators;
  List<TubeChannelInfo> _results = [];
  bool _saving = false;
  bool _searching = false;
  String? _error;
  int _searchGeneration = 0;
  static const types = [
    'Regular videos',
    'Shorts',
    'Music',
    'Education',
    'Gaming',
    'Entertainment',
    'News',
    'Podcasts',
    'Sports',
    'Technology'
  ];
  static const topics = [
    'Science',
    'Coding',
    'Cooking',
    'Travel',
    'Fitness',
    'Space',
    'Movies',
    'History',
    'Art',
    'Football',
    'Cricket',
    'Photography'
  ];

  @override
  void initState() {
    super.initState();
    _name =
        TextEditingController(text: widget.editing ? _profile.displayName : '');
    _handle = TextEditingController(text: _profile.username);
    _types = _profile.feedTypes.isEmpty
        ? {'Regular videos'}
        : _profile.feedTypes.toSet();
    _interests = _profile.interests.toSet();
    _creators = {
      for (final value in List<Map<String, dynamic>>.from(
          _profile.identity['creators'] ?? []))
        value['id'] as String: TubeChannelInfo.fromJson(value)
    };
  }

  @override
  void dispose() {
    _name.dispose();
    _handle.dispose();
    _creatorQuery.dispose();
    _topic.dispose();
    super.dispose();
  }

  Future<void> _findCreators() async {
    final query = _creatorQuery.text.trim();
    if (query.isEmpty) return;
    final generation = ++_searchGeneration;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final result = await TubeSearchService().search(query,
          filters: const TubeSearchFilters(contentType: 'channels'));
      if (mounted && generation == _searchGeneration) {
        setState(() => _results = result.channels);
      }
    } catch (_) {
      if (mounted) {
        setState(() =>
            _error = 'Channel search unavailable. You can skip this step.');
      }
    } finally {
      if (mounted && generation == _searchGeneration) {
        setState(() => _searching = false);
      }
    }
  }

  Future<void> _connect() async {
    final connected = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => const TubeAuthScreen()));
    if (connected != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await _profile.saveIdentity({
        'displayName': TubeSessionService().userChannelName,
        'username': '',
        'feedTypes': ['Regular videos'],
        'interests': <String>[],
        'creators': <Map<String, dynamic>>[],
      }, complete: true);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Connected. Enter your local display name below to finish setup.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _profile.saveIdentity({
        'displayName': _name.text,
        'username': _handle.text,
        'feedTypes': _types.toList(),
        'interests': _interests.toList(),
        'creators': _creators.values.map((c) => c.toJson()).toList(),
      }, complete: !widget.editing);
      if (mounted && widget.editing) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not save your profile. $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _chips(List<String> choices, Set<String> selected) => Wrap(
        spacing: 8,
        runSpacing: 6,
        children: choices
            .map((value) => FilterChip(
                  label: Text(value),
                  selected: selected.contains(value),
                  onSelected: _saving
                      ? null
                      : (active) => setState(() {
                            active
                                ? selected.add(value)
                                : selected.remove(value);
                          }),
                ))
            .toList(),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: Text(widget.editing
                ? 'Edit local profile'
                : 'Welcome to ShreyX Tube')),
        body: Center(
            child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Form(
              key: _form,
              child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Icon(Icons.privacy_tip_outlined, size: 48),
                        const SizedBox(height: 16),
                        Text(
                            widget.editing
                                ? 'Make it yours'
                                : 'Your videos. Your device.',
                            style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 8),
                        const Text(
                            'Guest profiles and learning stay on this device. Public searches contact YouTube. Connecting an account is optional.'),
                        const SizedBox(height: 24),
                        if (!widget.editing) ...[
                          Card(
                              child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Row(children: [
                                          const Expanded(
                                              child: Text(
                                                  'Connect YouTube Account (Optional)',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600))),
                                          IconButton(
                                              tooltip:
                                                  'About connecting YouTube',
                                              icon: const Icon(
                                                  Icons.help_outline),
                                              onPressed: () => showDialog<void>(
                                                  context: context,
                                                  builder: (context) =>
                                                      AlertDialog(
                                                        title: const Text(
                                                            'Optional Connected Mode'),
                                                        content: const Text(
                                                            tubeConnectExplanation),
                                                        actions: [
                                                          TextButton(
                                                              onPressed: () =>
                                                                  Navigator.pop(
                                                                      context),
                                                              child: const Text(
                                                                  'Got it'))
                                                        ],
                                                      ))),
                                        ]),
                                        FilledButton(
                                            onPressed:
                                                _saving ? null : _connect,
                                            child: const Text(
                                                'Connect YouTube Account')),
                                        TextButton(
                                            onPressed: _saving
                                                ? null
                                                : () => FocusScope.of(context)
                                                    .nextFocus(),
                                            child: const Text(
                                                'Skip and Continue as Guest')),
                                      ]))),
                          const SizedBox(height: 16),
                        ],
                        TextFormField(
                            controller: _name,
                            maxLength: 60,
                            decoration: const InputDecoration(
                                labelText: 'Display name'),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                    ? 'Enter a display name'
                                    : null),
                        TextFormField(
                            controller: _handle,
                            maxLength: 30,
                            decoration: const InputDecoration(
                                labelText: 'Handle (optional)',
                                prefixText: '@'),
                            validator: (value) => value != null &&
                                    value.isNotEmpty &&
                                    !RegExp(r'^[a-zA-Z0-9_.-]{2,30}$')
                                        .hasMatch(value)
                                ? 'Use 2–30 letters, numbers, dots, dashes or underscores'
                                : null),
                        if (!widget.editing) ...[
                          const SizedBox(height: 24),
                          Text('What do you like to watch?',
                              style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 8),
                          _chips(types, _types),
                          const SizedBox(height: 24),
                          Text('Pick your interests',
                              style: Theme.of(context).textTheme.titleLarge),
                          const Text(
                              'Optional — choose a few, add your own, or skip.'),
                          const SizedBox(height: 8),
                          _chips(
                              {...topics, ..._interests}.toList(), _interests),
                          Row(children: [
                            Expanded(
                                child: TextField(
                                    controller: _topic,
                                    maxLength: 60,
                                    decoration: const InputDecoration(
                                        labelText: 'Add a topic'))),
                            IconButton(
                                tooltip: 'Add topic',
                                icon: const Icon(Icons.add),
                                onPressed: () {
                                  if (_topic.text.trim().isNotEmpty) {
                                    setState(() =>
                                        _interests.add(_topic.text.trim()));
                                  }
                                  _topic.clear();
                                })
                          ]),
                          const SizedBox(height: 24),
                          Text('Favorite creators',
                              style: Theme.of(context).textTheme.titleLarge),
                          const Text(
                              'Optional — find real channels, or skip for now.'),
                          Row(children: [
                            Expanded(
                                child: TextField(
                                    controller: _creatorQuery,
                                    decoration: const InputDecoration(
                                        labelText: 'Search channels'),
                                    onSubmitted: (_) => _findCreators())),
                            IconButton(
                                tooltip: 'Find channels',
                                onPressed: _searching ? null : _findCreators,
                                icon: const Icon(Icons.search))
                          ]),
                          if (_searching) const LinearProgressIndicator(),
                          if (!_searching &&
                              _creatorQuery.text.isNotEmpty &&
                              _results.isEmpty)
                            const Padding(
                                padding: EdgeInsets.all(8),
                                child: Text(
                                    'No public channel results yet. Try another name or skip.')),
                          ..._results.take(8).map((channel) => CheckboxListTile(
                              title: Text(channel.title),
                              subtitle: Text(channel.handle.isEmpty
                                  ? channel.id
                                  : channel.handle),
                              value: _creators.containsKey(channel.id),
                              onChanged: (checked) => setState(() {
                                    checked == true
                                        ? _creators[channel.id] = channel
                                        : _creators.remove(channel.id);
                                  }))),
                          if (_creators.isNotEmpty)
                            Text('${_creators.length} creator(s) selected'),
                          Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                  onPressed: () => setState(() {
                                        _interests.clear();
                                        _creators.clear();
                                        _results.clear();
                                      }),
                                  child: const Text(
                                      'Skip optional interests and creators'))),
                        ],
                        if (_error != null)
                          Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Text(_error!,
                                  style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error))),
                        const SizedBox(height: 24),
                        FilledButton(
                            onPressed: _saving ? null : _save,
                            child: Text(_saving
                                ? 'Saving…'
                                : widget.editing
                                    ? 'Save profile'
                                    : 'Start watching')),
                        const SizedBox(height: 24),
                      ]))),
        )),
      );
}
