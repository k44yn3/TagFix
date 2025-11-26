import 'dart:convert';
import 'package:http/http.dart' as http;

class MusicBrainzService {
  static const String _baseUrl = 'https://musicbrainz.org/ws/2';
  static const String _coverArtUrl = 'https://coverartarchive.org';
  static const String _userAgent = 'TagFix/1.0 (https://github.com/tagfix)';
  
  DateTime? _lastRequestTime;
  
  Future<List<MusicBrainzRelease>> searchReleases({
    required String artist,
    required String album,
    int limit = 5,
  }) async {
    await _enforceRateLimit();
    
    final query = 'artist:"$artist" AND release:"$album"';
    final encodedQuery = Uri.encodeComponent(query);
    final url = Uri.parse('$_baseUrl/release?query=$encodedQuery&fmt=json&limit=$limit');
    
    try {
      final response = await http.get(
        url,
        headers: {'User-Agent': _userAgent},
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final releases = data['releases'] as List<dynamic>?;
        
        if (releases == null || releases.isEmpty) {
          return [];
        }
        
        return releases
            .map((release) => MusicBrainzRelease.fromJson(release))
            .toList();
      } else {
        throw Exception('MusicBrainz API error: ${response.statusCode}');
      }
    } catch (e) {
      print('Error searching MusicBrainz: $e');
      return [];
    }
  }
  
  Future<List<int>?> getCoverArt(String mbid) async {
    await _enforceRateLimit();
    
    final url = Uri.parse('$_coverArtUrl/release/$mbid/front');
    
    try {
      final response = await http.get(
        url,
        headers: {'User-Agent': _userAgent},
      );
      
      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else if (response.statusCode == 404) {
        print('No cover art found for release $mbid');
        return null;
      } else {
        throw Exception('Cover Art Archive error: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching cover art: $e');
      return null;
    }
  }
  
  Future<void> _enforceRateLimit() async {
    if (_lastRequestTime != null) {
      final elapsed = DateTime.now().difference(_lastRequestTime!);
      if (elapsed.inMilliseconds < 1000) {
        await Future.delayed(Duration(milliseconds: 1000 - elapsed.inMilliseconds));
      }
    }
    _lastRequestTime = DateTime.now();
  }
}

class MusicBrainzRelease {
  final String id;
  final String title;
  final String? artist;
  final String? date;
  final String? country;
  
  MusicBrainzRelease({
    required this.id,
    required this.title,
    this.artist,
    this.date,
    this.country,
  });
  
  factory MusicBrainzRelease.fromJson(Map<String, dynamic> json) {
    String? artistName;
    if (json['artist-credit'] != null && json['artist-credit'] is List) {
      final artistCredit = json['artist-credit'] as List;
      if (artistCredit.isNotEmpty) {
        artistName = artistCredit[0]['artist']?['name'];
      }
    }
    
    return MusicBrainzRelease(
      id: json['id'] as String,
      title: json['title'] as String,
      artist: artistName,
      date: json['date'] as String?,
      country: json['country'] as String?,
    );
  }
  
  String get displayName {
    final parts = <String>[title];
    if (artist != null) parts.add('by $artist');
    if (date != null) parts.add('($date)');
    if (country != null) parts.add('[$country]');
    return parts.join(' ');
  }
}
