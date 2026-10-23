import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/tube_models.dart';
import 'tube_youtube_link.dart';

class TubeShareService {
  static const channel = MethodChannel('com.shreyx.tube/share');
  static Future<void> exportText(
    BuildContext context,
    String title,
    String text,
  ) async {
    if (text.length > 32000) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Export is limited to 32,000 characters. Copy or shorten the notes instead.',
            ),
          ),
        );
      }
      return;
    }
    var opened = false;
    try {
      opened = await channel.invokeMethod<bool>('shareText', {
            'title': title,
            'text': text,
          }) ??
          false;
    } on PlatformException {
      /* A visible retry message follows. */
    } on MissingPluginException {
      /* Platform export unavailable. */
    }
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not export study materials. Retry or copy them.',
          ),
        ),
      );
    }
  }

  static Future<void> share(BuildContext context, TubeVideoItem video) async {
    var opened = false;
    try {
      if (TubeYoutubeLink.parse(video.watchUrl) != null) {
        opened = await channel.invokeMethod<bool>('shareVideo', {
              'url': video.watchUrl,
              'title': video.title,
            }) ??
            false;
      }
    } on PlatformException {
      // Report failure without silently replacing the user's share action.
    } on MissingPluginException {
      // Android owns the native Sharesheet.
    }
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the share menu. Retry.')),
      );
    }
  }
}
