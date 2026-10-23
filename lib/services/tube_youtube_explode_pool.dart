import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class TubeYoutubeExplodePool {
  static final TubeYoutubeExplodePool instance = TubeYoutubeExplodePool._();
  
  TubeYoutubeExplodePool._();
  
  late final YoutubeExplode yt = YoutubeExplode();
  
  void dispose() => yt.close();
}
