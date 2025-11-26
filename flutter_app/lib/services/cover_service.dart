import 'dart:convert';
import 'package:http/http.dart' as http;
import 'musicbrainz_service.dart';

class CoverService {
  final MusicBrainzService _musicBrainzService = MusicBrainzService();
  
  Future<List<int>?> fetchCover(String artist, String album) async {
    try {
      final itunesCover = await _fetchFromItunes(artist, album);
      if (itunesCover != null) {
        return itunesCover;
      }
    } catch (e) {
      print('iTunes fetch error: $e');
    }
    
    try {
      final releases = await _musicBrainzService.searchReleases(
        artist: artist, 
        album: album,
        limit: 1
      );
      
      if (releases.isNotEmpty) {
        return await _musicBrainzService.getCoverArt(releases.first.id);
      }
    } catch (e) {
      print('MusicBrainz fetch error: $e');
    }
    
    return null;
  }
  
  Future<List<int>?> _fetchFromItunes(String artist, String album) async {
    final query = '$artist $album';
    final url = Uri.parse('https://itunes.apple.com/search?term=${Uri.encodeComponent(query)}&media=music&entity=album&limit=1');
    
    final response = await http.get(url);
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['resultCount'] > 0) {
        String artworkUrl = data['results'][0]['artworkUrl100'];
        artworkUrl = artworkUrl.replaceAll('100x100bb', '1000x1000bb');
        
        final imageResponse = await http.get(Uri.parse(artworkUrl));
        if (imageResponse.statusCode == 200) {
          return imageResponse.bodyBytes;
        }
      }
    }
    return null;
  }
}
