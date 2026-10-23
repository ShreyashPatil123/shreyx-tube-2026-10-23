import 'package:flutter/material.dart';
import '../screens/tube_auth_screen.dart';
import '../services/tube_session_service.dart';
import '../services/tube_storage_service.dart';

class TubeAccountAction extends StatelessWidget {
  const TubeAccountAction({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable:
            Listenable.merge([TubeSessionService(), TubeStorageService()]),
        builder: (context, _) {
          final session = TubeSessionService();
          return IconButton(
            tooltip: session.isLoggedIn
                ? 'YouTube account'
                : 'Connect YouTube Account',
            icon: session.isLoggedIn && !TubeStorageService().isIncognito
                ? CircleAvatar(
                    radius: 14,
                    foregroundImage: session.userAvatarUrl.isEmpty
                        ? null
                        : NetworkImage(session.userAvatarUrl),
                    child: Text(session.userChannelName.isEmpty
                        ? '?'
                        : session.userChannelName.characters.first))
                : const Icon(Icons.account_circle_outlined),
            onPressed: () async {
              if (!session.isLoggedIn) {
                await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const TubeAuthScreen()));
                return;
              }
              await showModalBottomSheet<void>(
                  context: context,
                  builder: (sheetContext) => SafeArea(
                        child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(session.userChannelName,
                                    style:
                                        Theme.of(context).textTheme.titleLarge),
                                if (session.userHandle.isNotEmpty)
                                  Text(session.userHandle),
                                const SizedBox(height: 12),
                                Text(session.hasPrivateConnection
                                    ? 'YouTube’s returned recommendations power the native feed. Your session is encrypted on this device. Incognito uses Guest requests. Disconnect deletes this connection and keeps your Guest preferences. Watching here does not write to YouTube history.'
                                    : 'Channel and subscriptions use Google’s official read-only API. Home and Shorts keep Guest discovery. Disconnect removes this app’s connection and revokes its Google access; other apps remain signed in.'),
                                const SizedBox(height: 12),
                                FilledButton.tonal(
                                    onPressed: () async {
                                      Navigator.pop(sheetContext);
                                      try {
                                        await session.clearSession();
                                      } catch (_) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(const SnackBar(
                                                  content: Text(
                                                      'Session cleanup failed. Retry disconnecting from Privacy settings.')));
                                        }
                                      }
                                    },
                                    child: const Text('Sign Out / Disconnect')),
                              ],
                            )),
                      ));
            },
          );
        },
      );
}
