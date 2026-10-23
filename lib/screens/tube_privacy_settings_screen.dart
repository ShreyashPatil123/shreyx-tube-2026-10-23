import 'package:flutter/material.dart';
import '../services/tube_session_service.dart';
import 'tube_device_setup_screen.dart';
import 'tube_ai_privacy_screen.dart';
import '../widgets/tube_account_action.dart';
import '../services/tube_storage_service.dart';
import '../services/tube_database_service.dart';
import '../services/tube_local_reset_service.dart';
import '../providers/tube_player_provider.dart';
import '../providers/tube_shorts_controller.dart';
import 'package:provider/provider.dart';

class TubePrivacySettingsScreen extends StatefulWidget {
  const TubePrivacySettingsScreen({super.key});

  @override
  State<TubePrivacySettingsScreen> createState() =>
      _TubePrivacySettingsScreenState();
}

class _TubePrivacySettingsScreenState extends State<TubePrivacySettingsScreen> {
  final TubeStorageService _storageService = TubeStorageService();
  Map<String, dynamic> _storageBreakdown = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStorageInfo();
  }

  Future<void> _loadStorageInfo() async {
    final info = await _storageService.getStorageUsageBreakdown();
    if (mounted) {
      setState(() {
        _storageBreakdown = info;
        _isLoading = false;
      });
    }
  }

  void _confirmAction(
      {required String title,
      required String message,
      required VoidCallback onConfirm,
      String confirmLabel = 'Confirm'}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text(title,
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: Text(message,
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE50914)),
            onPressed: () {
              Navigator.pop(ctx);
              onConfirm();
            },
            child:
                Text(confirmLabel, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        elevation: 0,
        title: const Text('Privacy & Local Data',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          // 1. ShreyX Privacy Assurance Banner
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF141414),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white12),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.verified_user_outlined,
                        color: Colors.greenAccent, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Your privacy choices',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.white),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  '• No account required — ever.\n'
                  '• Guest history, playlists and follows stay on this device.\n'
                  '• No custom telemetry or proxy servers.\n'
                  '• Optional YouTube connection uses your account’s returned recommendations. Guest preferences stay local. Incognito uses Guest requests.',
                  style: TextStyle(
                      fontSize: 12, color: Colors.white70, height: 1.5),
                ),
              ],
            ),
          ),

          const ListTile(
              title: Text('YouTube account (optional)'),
              subtitle: Text(
                  'Connect or disconnect without changing your Guest profile'),
              trailing: TubeAccountAction()),
          ListTile(
            leading: const Icon(Icons.auto_awesome_outlined),
            title: const Text('AI processing and study data'),
            subtitle: const Text(
                'Local by default, optional external AI, clear saved responses and notes'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const TubeAiPrivacyScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.open_in_new),
            title: const Text('YouTube link opening'),
            subtitle: const Text(
                'Check supported links, YouTube defaults, notifications and picture-in-picture.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const TubeDeviceSetupScreen())),
          ),
          ListTile(
              title: const Text('Clear connected session'),
              leading: const Icon(Icons.logout),
              onTap: () async {
                try {
                  await TubeSessionService().clearSession();
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Session cleanup failed. Retry.')));
                  }
                }
              }),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 6),
            child: Text('PRIVACY MODES',
                style: TextStyle(
                    color: Color(0xFFE50914),
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
          ),

          // Incognito Mode Toggle
          SwitchListTile(
            activeThumbColor: const Color(0xFFE50914),
            secondary:
                const Icon(Icons.visibility_off, color: Colors.amberAccent),
            title: const Text('Incognito Mode',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
            subtitle: const Text(
                'Use Guest requests and pause local watch history, search queries and resume recording.',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            value: _storageService.isIncognito,
            onChanged: (val) async {
              await _storageService.setIncognito(val);
              setState(() {});
            },
          ),

          // Pause Watch History
          SwitchListTile(
            activeThumbColor: const Color(0xFFE50914),
            secondary:
                const Icon(Icons.history_toggle_off, color: Colors.white70),
            title: const Text('Pause Watch History',
                style: TextStyle(color: Colors.white, fontSize: 14)),
            subtitle: const Text(
                'Stop recording videos to your local watch history.',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            value: _storageService.pauseWatchHistory,
            onChanged: (val) async {
              await _storageService.setPauseWatchHistory(val);
              setState(() {});
            },
          ),

          // Pause Search History
          SwitchListTile(
            activeThumbColor: const Color(0xFFE50914),
            secondary: const Icon(Icons.search_off, color: Colors.white70),
            title: const Text('Pause Search History',
                style: TextStyle(color: Colors.white, fontSize: 14)),
            subtitle: const Text(
                'Stop saving queries to your local search history.',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            value: _storageService.pauseSearchHistory,
            onChanged: (val) async {
              await _storageService.setPauseSearchHistory(val);
              setState(() {});
            },
          ),

          // Pause Local Personalization
          SwitchListTile(
            activeThumbColor: const Color(0xFFE50914),
            secondary: const Icon(Icons.tune, color: Colors.white70),
            title: const Text('Pause Local Recommendations',
                style: TextStyle(color: Colors.white, fontSize: 14)),
            subtitle: const Text(
                'Disable on-device ranking. Account subscriptions remain available unless you enable Incognito or disconnect.',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            value: _storageService.pausePersonalization,
            onChanged: (val) async {
              await _storageService.setPausePersonalization(val);
              setState(() {});
            },
          ),

          const Divider(color: Colors.white12, height: 32),

          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text('STORAGE USAGE (ON-DEVICE)',
                style: TextStyle(
                    color: Color(0xFFE50914),
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
          ),

          if (_isLoading)
            const Center(
                child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: CircularProgressIndicator(color: Color(0xFFE50914))))
          else ...[
            ListTile(
              leading:
                  const Icon(Icons.storage_outlined, color: Colors.white70),
              title: const Text('Total Local Data',
                  style: TextStyle(color: Colors.white, fontSize: 14)),
              trailing: Text(
                _storageBreakdown['formattedSize']?.toString() ?? '0 KB',
                style: const TextStyle(
                    color: Colors.greenAccent, fontWeight: FontWeight.bold),
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Text(
                '• History: ${_storageBreakdown["historyCount"]} videos\n'
                '• Search queries: ${_storageBreakdown["searchCount"]}\n'
                '• Watch Later: ${_storageBreakdown["watchLaterCount"]} videos\n'
                '• Local Playlists: ${_storageBreakdown["playlistsCount"]}\n'
                '• Followed Channels: ${_storageBreakdown["followedChannelsCount"]}',
                style: const TextStyle(
                    fontSize: 12, color: Colors.white54, height: 1.5),
              ),
            ),
          ],

          const Divider(color: Colors.white12, height: 32),

          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text('DATA DELETION CONTROLS',
                style: TextStyle(
                    color: Color(0xFFE50914),
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
          ),

          // Clear Watch History
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.white70),
            title: const Text('Clear Watch History',
                style: TextStyle(color: Colors.white, fontSize: 14)),
            onTap: () {
              final messenger = ScaffoldMessenger.of(context);
              _confirmAction(
                title: 'Clear Watch History?',
                message:
                    'This will erase all locally saved watch records and resume positions.',
                onConfirm: () async {
                  await _storageService.clearWatchHistory();
                  await TubeDatabaseService().clearWatchHistory();
                  await _loadStorageInfo();
                  messenger.showSnackBar(
                      const SnackBar(content: Text('Watch history cleared')));
                },
              );
            },
          ),

          // Clear Search History
          ListTile(
            leading: const Icon(Icons.clear_all, color: Colors.white70),
            title: const Text('Clear Search History',
                style: TextStyle(color: Colors.white, fontSize: 14)),
            onTap: () {
              final messenger = ScaffoldMessenger.of(context);
              _confirmAction(
                title: 'Clear Search History?',
                message: 'This will delete all saved search query suggestions.',
                onConfirm: () async {
                  await _storageService.clearSearchHistory();
                  await TubeDatabaseService().clearSearchHistory();
                  await _loadStorageInfo();
                  messenger.showSnackBar(
                      const SnackBar(content: Text('Search history cleared')));
                },
              );
            },
          ),

          // Clear All Local Data
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Color(0xFFE50914)),
            title: const Text('Clear All Local Data',
                style: TextStyle(
                    color: Color(0xFFE50914),
                    fontSize: 14,
                    fontWeight: FontWeight.bold)),
            subtitle: const Text(
                'Reset ShreyX Tube to fresh installation state on this device.',
                style: TextStyle(color: Colors.white38, fontSize: 11)),
            onTap: () {
              final messenger = ScaffoldMessenger.of(context);
              _confirmAction(
                title: 'Clear all local data?',
                message: tubeResetMessage,
                confirmLabel: 'Clear all data',
                onConfirm: () async {
                  final player = context.read<TubePlayerProvider>();
                  final shorts = context.read<TubeShortsController>();
                  try {
                    await TubeLocalResetService.reset(player, shorts);
                    await _loadStorageInfo();
                    if (!mounted) return;
                    if (context.mounted) {
                      Navigator.of(context, rootNavigator: true)
                          .popUntil((route) => route.isFirst);
                    }
                  } catch (e) {
                    messenger.showSnackBar(SnackBar(
                        content: Text(
                            'Reset did not finish. Retry to complete it. $e')));
                  }
                },
              );
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
