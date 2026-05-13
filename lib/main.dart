import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

// ═══════════════════════════════════════════════════════════
// TEMAS
// ═══════════════════════════════════════════════════════════
enum AppTheme { purple, spotify, yellow, white }

extension AppThemeExt on AppTheme {
  String get label {
    switch (this) {
      case AppTheme.purple:  return 'Morado';
      case AppTheme.spotify: return 'Spotify';
      case AppTheme.yellow:  return 'Amarillo';
      case AppTheme.white:   return 'Blanco';
    }
  }

  Color get primary {
    switch (this) {
      case AppTheme.purple:  return const Color(0xFF7C3AED);
      case AppTheme.spotify: return const Color(0xFF1DB954);
      case AppTheme.yellow:  return const Color(0xFFEAB308);
      case AppTheme.white:   return const Color(0xFFE2E8F0);
    }
  }

  Color get primaryDark {
    switch (this) {
      case AppTheme.purple:  return const Color(0xFF4C1D95);
      case AppTheme.spotify: return const Color(0xFF14833B);
      case AppTheme.yellow:  return const Color(0xFFCA8A04);
      case AppTheme.white:   return const Color(0xFF94A3B8);
    }
  }

  List<Color> get bgGradient {
    switch (this) {
      case AppTheme.purple:  return [const Color(0xFF1a1a2e), const Color(0xFF0D0D0D)];
      case AppTheme.spotify: return [const Color(0xFF0D1F14), const Color(0xFF0D0D0D)];
      case AppTheme.yellow:  return [const Color(0xFF1F1A0D), const Color(0xFF0D0D0D)];
      case AppTheme.white:   return [const Color(0xFFF8FAFC), const Color(0xFFE2E8F0)];
    }
  }

  Color get navBg         => this == AppTheme.white ? const Color(0xFFCBD5E1) : const Color(0xFF12121A);
  bool  get isDark        => this != AppTheme.white;
  Color get textPrimary   => isDark ? Colors.white            : const Color(0xFF1E293B);
  Color get textSecondary => isDark ? Colors.white54          : const Color(0xFF64748B);
  Color get textHint      => isDark ? Colors.white24          : const Color(0xFFCBD5E1);
  Color get cardBg        => isDark ? const Color(0xFF1E1E2E) : Colors.white;
  Color get iconInactive  => isDark ? Colors.white38          : const Color(0xFF94A3B8);
}

// ═══════════════════════════════════════════════════════════
// MODELO CANCIÓN
// ═══════════════════════════════════════════════════════════
class SongModel {
  final String  path;
  final String  title;
  final String  artist;
  final bool    isFavorite;
  final String? imagePath;

  const SongModel({
    required this.path,
    required this.title,
    required this.artist,
    this.isFavorite = false,
    this.imagePath,
  });

  SongModel copyWith({bool? isFavorite, String? imagePath}) => SongModel(
    path:       path,
    title:      title,
    artist:     artist,
    isFavorite: isFavorite ?? this.isFavorite,
    imagePath:  imagePath  ?? this.imagePath,
  );

  Map<String, dynamic> toJson() => {
    'path': path, 'title': title, 'artist': artist,
    'isFavorite': isFavorite, 'imagePath': imagePath,
  };

  factory SongModel.fromJson(Map<String, dynamic> j) => SongModel(
    path:       j['path'],
    title:      j['title'],
    artist:     j['artist'],
    isFavorite: j['isFavorite'] ?? false,
    imagePath:  j['imagePath'],
  );
}

// ═══════════════════════════════════════════════════════════
// MODELO PLAYLIST
// ═══════════════════════════════════════════════════════════
class PlaylistModel {
  final String id;
  String name;
  List<String> songPaths;

  PlaylistModel({required this.id, required this.name, List<String>? songPaths})
      : songPaths = songPaths ?? [];

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'songPaths': songPaths};

  factory PlaylistModel.fromJson(Map<String, dynamic> j) => PlaylistModel(
    id:        j['id']   as String,
    name:      j['name'] as String,
    songPaths: (j['songPaths'] as List<dynamic>).cast<String>(),
  );
}

// ═══════════════════════════════════════════════════════════
// ESTADO GLOBAL
// ═══════════════════════════════════════════════════════════
final _ps = PlayerState();

class PlayerState extends ChangeNotifier {
  final AudioPlayer   _player    = AudioPlayer();
  List<SongModel>     _songs     = [];
  List<PlaylistModel> _playlists = [];
  int      _currentIndex = -1;
  bool     _isPlaying    = false;
  Duration _position     = Duration.zero;
  Duration _duration     = Duration.zero;
  bool     repeat        = false;
  bool     shuffle       = false;
  int      _tab          = 0;
  AppTheme _theme        = AppTheme.purple;

  List<SongModel>     get songs        => _songs;
  List<PlaylistModel> get playlists    => _playlists;
  int      get currentIndex => _currentIndex;
  bool     get isPlaying    => _isPlaying;
  Duration get position     => _position;
  Duration get duration     => _duration;
  int      get tab          => _tab;
  AppTheme get theme        => _theme;
  SongModel? get currentSong =>
      (_currentIndex >= 0 && _currentIndex < _songs.length) ? _songs[_currentIndex] : null;

  PlayerState() {
    _player.onPositionChanged.listen((p) { _position = p; notifyListeners(); });
    _player.onDurationChanged.listen((d) { _duration = d; notifyListeners(); });
    _player.onPlayerComplete.listen((_) {
      if (repeat)       { play(_currentIndex); }
      else if (shuffle) { play((List.generate(_songs.length, (i) => i)..shuffle()).first); }
      else if (_currentIndex < _songs.length - 1) { play(_currentIndex + 1); }
      else              { _isPlaying = false; notifyListeners(); }
    });
    _loadSaved();
  }

  void setTab(int t)        { _tab = t; notifyListeners(); }
  void setTheme(AppTheme t) { _theme = t; _saveTheme(); notifyListeners(); }

  // ── Persistencia ─────────────────────────────────────────
  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final songsRaw = prefs.getString('songs');
    if (songsRaw != null) {
      _songs = (jsonDecode(songsRaw) as List)
          .map((e) => SongModel.fromJson(e as Map<String, dynamic>)).toList();
    }
    final plRaw = prefs.getString('playlists');
    if (plRaw != null) {
      _playlists = (jsonDecode(plRaw) as List)
          .map((e) => PlaylistModel.fromJson(e as Map<String, dynamic>)).toList();
    }
    final ti = prefs.getInt('theme_index') ?? 0;
    _theme = AppTheme.values[ti.clamp(0, AppTheme.values.length - 1)];
    notifyListeners();
  }

  Future<void> _saveSongs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('songs', jsonEncode(_songs.map((s) => s.toJson()).toList()));
  }

  Future<void> _savePlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('playlists', jsonEncode(_playlists.map((p) => p.toJson()).toList()));
  }

  Future<void> _saveTheme() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_index', _theme.index);
  }

  // ── Carpeta de música ─────────────────────────────────────
  // CAMBIO 1: Agrega canciones nuevas sin cerrar ni reiniciar la app.
  // Ya no se reemplaza _songs completo; se combinan las canciones nuevas
  // con las existentes evitando duplicados por ruta.
  Future<void> pickFolder() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result == null) return; // El usuario canceló, no hacer nada

    const ext = {'.mp3', '.wav', '.m4a', '.flac', '.ogg'};
    final files = Directory(result).listSync(recursive: true).whereType<File>()
        .where((f) {
          final dot = f.path.lastIndexOf('.');
          return dot >= 0 && ext.contains(f.path.substring(dot).toLowerCase());
        }).toList();

    final newSongs = files
        .where((f) => !_songs.any((s) => s.path == f.path)) // evita duplicados
        .map((f) {
          final name = f.path.split(Platform.pathSeparator).last;
          final dot  = name.lastIndexOf('.');
          return SongModel(
            path:   f.path,
            title:  dot >= 0 ? name.substring(0, dot) : name,
            artist: 'Desconocido',
          );
        }).toList();

    if (newSongs.isEmpty) return; // No había nada nuevo, no notificar

    _songs = [..._songs, ...newSongs]; // combinar en lugar de reemplazar
    // NO se toca _currentIndex ni se detiene el reproductor
    await _saveSongs();
    notifyListeners();
  }

  // ── Imagen por canción ────────────────────────────────────
  Future<void> pickImageForSong(int i) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'bmp', 'gif'],
    );
    if (result == null || result.files.single.path == null) return;
    _songs[i] = _songs[i].copyWith(imagePath: result.files.single.path);
    await _saveSongs();
    notifyListeners();
  }

  // ── Favoritos ─────────────────────────────────────────────
  void toggleFavorite(int i) {
    _songs[i] = _songs[i].copyWith(isFavorite: !_songs[i].isFavorite);
    _saveSongs();
    notifyListeners();
  }

  // ── Reproducción ──────────────────────────────────────────
  Future<void> play(int i) async {
    if (i < 0 || i >= _songs.length) return;
    _currentIndex = i;
    await _player.stop();
    await _player.play(DeviceFileSource(_songs[i].path));
    _isPlaying = true;
    notifyListeners();
  }

  Future<void> togglePlayPause() async {
    if (_currentIndex < 0 && _songs.isNotEmpty) { await play(0); return; }
    _isPlaying ? await _player.pause() : await _player.resume();
    _isPlaying = !_isPlaying;
    notifyListeners();
  }

  Future<void> seekTo(Duration p) => _player.seek(p);
  Future<void> next() async => play(
      shuffle ? (List.generate(_songs.length, (i) => i)..shuffle()).first
              : (_currentIndex + 1) % _songs.length);
  Future<void> prev() async =>
      play(_currentIndex > 0 ? _currentIndex - 1 : _songs.length - 1);
  void toggleRepeat()  { repeat  = !repeat;  notifyListeners(); }
  void toggleShuffle() { shuffle = !shuffle; notifyListeners(); }

  // ── CRUD Playlists ────────────────────────────────────────
  void createPlaylist(String name, List<String> paths) {
    _playlists.add(PlaylistModel(
      id:        DateTime.now().millisecondsSinceEpoch.toString(),
      name:      name,
      songPaths: paths,
    ));
    _savePlaylists();
    notifyListeners();
  }

  void renamePlaylist(String id, String newName) {
    _playlists.firstWhere((p) => p.id == id).name = newName;
    _savePlaylists();
    notifyListeners();
  }

  void deletePlaylist(String id) {
    _playlists.removeWhere((p) => p.id == id);
    _savePlaylists();
    notifyListeners();
  }

  void addSongToPlaylist(String id, String path) {
    final pl = _playlists.firstWhere((p) => p.id == id);
    if (!pl.songPaths.contains(path)) {
      pl.songPaths.add(path);
      _savePlaylists();
      notifyListeners();
    }
  }

  void removeSongFromPlaylist(String id, String path) {
    _playlists.firstWhere((p) => p.id == id).songPaths.remove(path);
    _savePlaylists();
    notifyListeners();
  }

  void reorderPlaylistSongs(String id, int oldIdx, int newIdx) {
    final pl = _playlists.firstWhere((p) => p.id == id);
    if (newIdx > oldIdx) newIdx--;
    final s = pl.songPaths.removeAt(oldIdx);
    pl.songPaths.insert(newIdx, s);
    _savePlaylists();
    notifyListeners();
  }

  void playPlaylist(PlaylistModel pl, int startIndex) {
    final indices = pl.songPaths
        .map((path) => _songs.indexWhere((s) => s.path == path))
        .where((i) => i >= 0)
        .toList();
    if (indices.isEmpty) return;
    play(indices[startIndex.clamp(0, indices.length - 1)]);
  }

  // ── Eliminar canción de la biblioteca ────────────────────
  void removeSong(int i) {
    if (i < 0 || i >= _songs.length) return;
    final wasPlaying = _currentIndex == i;
    final removedPath = _songs[i].path;
    _songs.removeAt(i);
    // Ajustar índice actual tras el borrado
    if (wasPlaying) {
      _isPlaying = false;
      _player.stop();
      _currentIndex = -1;
    } else if (_currentIndex > i) {
      _currentIndex--;
    }
    // Eliminar la canción de todas las playlists también
    for (final pl in _playlists) {
      pl.songPaths.remove(removedPath);
    }
    _saveSongs();
    _savePlaylists();
    notifyListeners();
  }

  // ── Agregar canción descargada ────────────────────────────
  void addDownloadedSong(String path) {
    if (_songs.any((s) => s.path == path)) return;
    final name  = path.split(Platform.pathSeparator).last;
    final dot   = name.lastIndexOf('.');
    final title = dot >= 0 ? name.substring(0, dot) : name;
    _songs.add(SongModel(path: path, title: title, artist: 'Desconocido'));
    _saveSongs();
    notifyListeners();
  }

  @override
  void dispose() { _player.dispose(); super.dispose(); }
}

// ═══════════════════════════════════════════════════════════
// MAIN + APP
// ═══════════════════════════════════════════════════════════
void main() => runApp(const MusicApp());

class MusicApp extends StatelessWidget {
  const MusicApp({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _ps,
    builder: (_, __) {
      final t = _ps.theme;
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Xonix',
        theme: (t.isDark
            ? ThemeData.dark(useMaterial3: true)
            : ThemeData.light(useMaterial3: true))
          .copyWith(
            colorScheme: (t.isDark ? ColorScheme.dark : ColorScheme.light)(primary: t.primary),
            scaffoldBackgroundColor: Colors.transparent,
          ),
        home: const SplashScreen(),
      );
    },
  );
}

// ═══════════════════════════════════════════════════════════
// SPLASH — XONIX → X
// ═══════════════════════════════════════════════════════════
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fadeIn, _collapse, _fadeOut;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800));
    _fadeIn   = CurvedAnimation(parent: _ctrl, curve: const Interval(0.00, 0.35, curve: Curves.easeIn));
    _collapse = CurvedAnimation(parent: _ctrl, curve: const Interval(0.45, 0.75, curve: Curves.easeInOut));
    _fadeOut  = CurvedAnimation(parent: _ctrl, curve: const Interval(0.80, 1.00, curve: Curves.easeOut));
    _ctrl.forward();
    _ctrl.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        Navigator.of(context).pushReplacement(PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 400),
          pageBuilder: (_, __, ___) => const HomeShell(),
          transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c),
        ));
      }
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF0D0D0D),
    body: Center(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => Opacity(
          opacity: (1 - _fadeOut.value).clamp(0.0, 1.0),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Opacity(
              opacity: _fadeIn.value,
              child: const Text('X', style: TextStyle(
                fontSize: 72, fontWeight: FontWeight.w900,
                color: Color(0xFF7C3AED), letterSpacing: -2))),
            ClipRect(
              child: Align(
                alignment: Alignment.centerLeft,
                widthFactor: (1 - _collapse.value).clamp(0.0, 1.0),
                child: Opacity(
                  opacity: _fadeIn.value,
                  child: const Text('ONIX', style: TextStyle(
                    fontSize: 72, fontWeight: FontWeight.w900,
                    color: Colors.white, letterSpacing: -2))))),
          ]),
        ),
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════════════
// HOME SHELL — 5 tabs
// ═══════════════════════════════════════════════════════════
class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  static const _labels = ['Biblioteca', 'Reproduciendo', 'Favoritos', 'Listas', 'Descargar'];
  static const _icons  = [
    Icons.library_music_rounded,
    Icons.queue_music_rounded,
    Icons.favorite_rounded,
    Icons.playlist_play_rounded,
    Icons.download_rounded,
  ];

  static void showThemePicker(BuildContext context) {
    final t = _ps.theme;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: t.isDark ? const Color(0xFF1E1E2E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[600], borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          Text('Elige un tema', style: TextStyle(
            fontSize: 18, fontWeight: FontWeight.bold, color: t.textPrimary)),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: AppTheme.values.map((theme) {
              final selected = _ps.theme == theme;
              return GestureDetector(
                onTap: () { _ps.setTheme(theme); Navigator.pop(context); },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 72, height: 96,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: selected ? theme.primary : Colors.transparent, width: 3),
                    color: theme.isDark ? const Color(0xFF12121A) : const Color(0xFFF1F5F9),
                    boxShadow: selected
                        ? [BoxShadow(color: theme.primary.withOpacity(0.4),
                              blurRadius: 14, spreadRadius: 2)]
                        : []),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(
                      width: 38, height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [theme.primary, theme.primaryDark],
                          begin: Alignment.topLeft, end: Alignment.bottomRight))),
                    const SizedBox(height: 8),
                    Text(theme.label, style: TextStyle(
                      fontSize: 11, color: t.textSecondary,
                      fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
                  ]),
                ),
              );
            }).toList(),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _ps,
    builder: (ctx, __) {
      final t    = _ps.theme;
      final wide = MediaQuery.of(ctx).size.width >= 720;
      const pages = [
        LibraryScreen(),
        NowPlayingScreen(),
        FavoritesScreen(),
        PlaylistsScreen(),
        DownloadScreen(),
      ];

      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: t.bgGradient)),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: wide
            ? Row(children: [
                NavigationRail(
                  backgroundColor: t.navBg,
                  selectedIndex: _ps.tab,
                  onDestinationSelected: _ps.setTab,
                  labelType: NavigationRailLabelType.all,
                  selectedIconTheme:      IconThemeData(color: t.primary),
                  selectedLabelTextStyle: TextStyle(color: t.primary),
                  unselectedIconTheme:    IconThemeData(color: t.iconInactive),
                  leading: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Column(children: [
                      GestureDetector(
                        onTap: () => showThemePicker(ctx),
                        child: Text('X', style: TextStyle(
                          color: t.primary, fontSize: 32, fontWeight: FontWeight.w900))),
                      Text('ONIX', style: TextStyle(
                        color: t.textSecondary, fontSize: 10,
                        fontWeight: FontWeight.bold, letterSpacing: 2)),
                    ]),
                  ),
                  destinations: List.generate(5, (i) => NavigationRailDestination(
                    icon: Icon(_icons[i]), label: Text(_labels[i]))),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: pages[_ps.tab]),
              ])
            : Column(children: [
                Expanded(child: pages[_ps.tab]),
                NavigationBar(
                  backgroundColor: t.navBg,
                  selectedIndex: _ps.tab,
                  onDestinationSelected: _ps.setTab,
                  destinations: List.generate(5, (i) => NavigationDestination(
                    icon: Icon(_icons[i],
                      color: _ps.tab == i ? t.primary : t.iconInactive),
                    label: _labels[i])),
                ),
              ]),
        ),
      );
    },
  );
}

// ═══════════════════════════════════════════════════════════
// SONG TILE — reutilizable
// ═══════════════════════════════════════════════════════════
class SongTile extends StatelessWidget {
  final SongModel song;
  final int       globalIndex;
  final bool      active;
  final bool      showAddToPlaylist;

  const SongTile({
    super.key,
    required this.song,
    required this.globalIndex,
    required this.active,
    this.showAddToPlaylist = false,
  });

  void _confirmDelete(BuildContext context) {
    final t = _ps.theme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.isDark ? const Color(0xFF1E1E2E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Eliminar canción', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold)),
        content: Text(
          '¿Eliminar "${song.title}" de tu biblioteca?\nNo se borrará el archivo del disco.',
          style: TextStyle(color: t.textSecondary, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancelar', style: TextStyle(color: t.textSecondary))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(ctx);
              _ps.removeSong(globalIndex);
            },
            child: const Text('Eliminar')),
        ],
      ),
    );
  }

  void _showAddToPlaylist(BuildContext context) {
    final t = _ps.theme;
    if (_ps.playlists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Primero crea una lista en la pestaña Listas'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: t.primary));
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: t.isDark ? const Color(0xFF1E1E2E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[600], borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Text('Agregar a lista', style: TextStyle(
            fontSize: 18, fontWeight: FontWeight.bold, color: t.textPrimary)),
          const SizedBox(height: 16),
          ..._ps.playlists.map((pl) {
            final already = pl.songPaths.contains(song.path);
            return ListTile(
              leading: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: t.primary.withOpacity(0.15)),
                child: Icon(Icons.queue_music_rounded, color: t.primary, size: 20)),
              title: Text(pl.name, style: TextStyle(
                color: t.textPrimary, fontWeight: FontWeight.w600)),
              subtitle: Text('${pl.songPaths.length} canciones',
                style: TextStyle(color: t.textSecondary, fontSize: 12)),
              trailing: already
                  ? Icon(Icons.check_circle_rounded, color: t.primary)
                  : Icon(Icons.add_circle_outline_rounded, color: t.iconInactive),
              onTap: () {
                if (!already) {
                  _ps.addSongToPlaylist(pl.id, song.path);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Agregada a "${pl.name}"'),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: t.primary));
                }
              },
            );
          }),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = _ps.theme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: GestureDetector(
        onTap: () => _ps.pickImageForSong(globalIndex),
        child: Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: active ? t.primary.withOpacity(0.2) : t.cardBg,
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3))]),
          clipBehavior: Clip.antiAlias,
          // CAMBIO 2: Si hay imagen se muestra, si no muestra la inicial del título.
          // Si está reproduciendo activamente, muestra el ícono de ecualizador animado.
          child: song.imagePath != null
              ? Image.file(File(song.imagePath!), fit: BoxFit.cover)
              : active && _ps.isPlaying
                  ? Icon(Icons.graphic_eq_rounded, color: t.primary)
                  : Center(
                      child: Text(
                        song.title.isNotEmpty ? song.title[0].toUpperCase() : '?',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: active ? t.primary : t.iconInactive,
                        ),
                      ),
                    ),
        ),
      ),
      title: Text(song.title,
        maxLines: 1, overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: active ? FontWeight.bold : FontWeight.normal,
          color:      active ? t.primary      : t.textPrimary)),
      subtitle: Text(song.artist,
        style: TextStyle(color: t.textSecondary, fontSize: 12)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (active && _ps.isPlaying)
          Icon(Icons.volume_up_rounded, color: t.primary, size: 16),
        const SizedBox(width: 4),
        if (showAddToPlaylist) ...[
          GestureDetector(
            onTap: () => _showAddToPlaylist(context),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white10),
              child: Icon(Icons.playlist_add_rounded, color: t.primary, size: 18))),
          const SizedBox(width: 4),
        ],
        GestureDetector(
          onTap: () => _ps.toggleFavorite(globalIndex),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: song.isFavorite
                  ? LinearGradient(colors: [t.primary, t.primaryDark])
                  : null,
              color: song.isFavorite ? null : Colors.white10),
            child: Icon(
              song.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: song.isFavorite ? Colors.white : t.iconInactive,
              size: 18))),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: () => _confirmDelete(context),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white10),
            child: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18))),
      ]),
      onTap: () { _ps.play(globalIndex); _ps.setTab(1); },
    );
  }
}

// ═══════════════════════════════════════════════════════════
// PANTALLA: BIBLIOTECA
// ═══════════════════════════════════════════════════════════
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _ps,
    builder: (ctx, __) {
      final t = _ps.theme;
      return Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 48, 20, 16),
          child: Row(children: [
            Text('Tu biblioteca', style: TextStyle(
              fontSize: 24, fontWeight: FontWeight.bold, color: t.textPrimary)),
            const Spacer(),
            IconButton(
              onPressed: () => HomeShell.showThemePicker(ctx),
              icon: Icon(Icons.palette_rounded, color: t.primary),
              tooltip: 'Cambiar tema'),
            const SizedBox(width: 4),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: t.primary,
                foregroundColor: t.isDark ? Colors.white : Colors.black),
              onPressed: _ps.pickFolder,
              icon: const Icon(Icons.folder_open_rounded),
              label: const Text('Abrir carpeta')),
          ]),
        ),
        if (_ps.songs.isEmpty)
          Expanded(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.folder_off_rounded, size: 72, color: t.textHint),
            const SizedBox(height: 16),
            Text('Sin canciones', style: TextStyle(color: t.textSecondary, fontSize: 18)),
            const SizedBox(height: 8),
            Text('Abre una carpeta con archivos de audio',
              style: TextStyle(color: t.textHint, fontSize: 13)),
          ])))
        else
          Expanded(child: ListView.builder(
            itemCount: _ps.songs.length,
            itemBuilder: (_, i) => SongTile(
              song: _ps.songs[i], globalIndex: i,
              active: _ps.currentIndex == i,
              showAddToPlaylist: true),
          )),
      ]);
    },
  );
}

// ═══════════════════════════════════════════════════════════
// PANTALLA: FAVORITOS
// ═══════════════════════════════════════════════════════════
class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _ps,
    builder: (_, __) {
      final t      = _ps.theme;
      final favIdx = List.generate(_ps.songs.length, (i) => i)
          .where((i) => _ps.songs[i].isFavorite).toList();
      return Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 48, 20, 16),
          child: Row(children: [
            Icon(Icons.favorite_rounded, color: t.primary, size: 28),
            const SizedBox(width: 10),
            Text('Favoritos', style: TextStyle(
              fontSize: 24, fontWeight: FontWeight.bold, color: t.textPrimary)),
          ]),
        ),
        if (favIdx.isEmpty)
          Expanded(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.favorite_border_rounded, size: 72, color: t.textHint),
            const SizedBox(height: 16),
            Text('Sin favoritos aún', style: TextStyle(color: t.textSecondary, fontSize: 18)),
            const SizedBox(height: 8),
            Text('Toca el corazón en cualquier canción',
              style: TextStyle(color: t.textHint, fontSize: 13)),
          ])))
        else
          Expanded(child: ListView.builder(
            itemCount: favIdx.length,
            itemBuilder: (_, i) {
              final gi = favIdx[i];
              return SongTile(
                song: _ps.songs[gi], globalIndex: gi,
                active: _ps.currentIndex == gi,
                showAddToPlaylist: true);
            },
          )),
      ]);
    },
  );
}

// ═══════════════════════════════════════════════════════════
// PANTALLA: LISTAS
// ═══════════════════════════════════════════════════════════
class PlaylistsScreen extends StatelessWidget {
  const PlaylistsScreen({super.key});

  void _showCreateDialog(BuildContext context) {
    final t        = _ps.theme;
    final selected = <String>{};
    final nameCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Dialog(
          backgroundColor: t.isDark ? const Color(0xFF1E1E2E) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Nueva lista', style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold, color: t.textPrimary)),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtrl, autofocus: true,
                style: TextStyle(color: t.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Nombre de la lista...',
                  hintStyle: TextStyle(color: t.textHint),
                  filled: true,
                  fillColor: t.isDark ? Colors.white10 : Colors.black12,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: t.primary, width: 1.5))),
              ),
              if (_ps.songs.isNotEmpty) ...[
                const SizedBox(height: 16),
                Align(alignment: Alignment.centerLeft,
                  child: Text('Canciones (${selected.length})',
                    style: TextStyle(color: t.textSecondary, fontSize: 13,
                      fontWeight: FontWeight.w600))),
                const SizedBox(height: 8),
                SizedBox(
                  height: 240,
                  child: ListView.builder(
                    itemCount: _ps.songs.length,
                    itemBuilder: (_, i) {
                      final s   = _ps.songs[i];
                      final sel = selected.contains(s.path);
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                        leading: Checkbox(
                          value: sel, activeColor: t.primary,
                          onChanged: (_) => setS(() =>
                            sel ? selected.remove(s.path) : selected.add(s.path))),
                        title: Text(s.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: t.textPrimary, fontSize: 13)),
                        onTap: () => setS(() =>
                          sel ? selected.remove(s.path) : selected.add(s.path)),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Cancelar', style: TextStyle(color: t.textSecondary))),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: t.primary),
                  onPressed: () {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) return;
                    _ps.createPlaylist(name, selected.toList());
                    Navigator.pop(ctx);
                  },
                  child: const Text('Crear')),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _ps,
    builder: (ctx, __) {
      final t = _ps.theme;
      return Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 48, 20, 16),
          child: Row(children: [
            Icon(Icons.playlist_play_rounded, color: t.primary, size: 28),
            const SizedBox(width: 10),
            Text('Listas', style: TextStyle(
              fontSize: 24, fontWeight: FontWeight.bold, color: t.textPrimary)),
            const Spacer(),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: t.primary, foregroundColor: Colors.white),
              onPressed: () => _showCreateDialog(ctx),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Nueva lista')),
          ]),
        ),
        if (_ps.playlists.isEmpty)
          Expanded(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.queue_music_rounded, size: 72, color: t.textHint),
            const SizedBox(height: 16),
            Text('Sin listas aún', style: TextStyle(color: t.textSecondary, fontSize: 18)),
            const SizedBox(height: 8),
            Text('Toca "Nueva lista" para crear una',
              style: TextStyle(color: t.textHint, fontSize: 13)),
          ])))
        else
          Expanded(child: ListView.builder(
            itemCount: _ps.playlists.length,
            itemBuilder: (_, i) => _PlaylistCard(playlist: _ps.playlists[i]),
          )),
      ]);
    },
  );
}

// ───────────────────────────────────────────────
// CARD PLAYLIST
// ───────────────────────────────────────────────
class _PlaylistCard extends StatelessWidget {
  final PlaylistModel playlist;
  const _PlaylistCard({required this.playlist});

  void _showRenameDialog(BuildContext context) {
    final t    = _ps.theme;
    final ctrl = TextEditingController(text: playlist.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.isDark ? const Color(0xFF1E1E2E) : Colors.white,
        title: Text('Renombrar lista', style: TextStyle(color: t.textPrimary)),
        content: TextField(
          controller: ctrl, autofocus: true,
          style: TextStyle(color: t.textPrimary),
          decoration: InputDecoration(
            filled: true,
            fillColor: t.isDark ? Colors.white10 : Colors.black12,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: t.primary, width: 1.5))),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancelar', style: TextStyle(color: t.textSecondary))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: t.primary),
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isNotEmpty) _ps.renamePlaylist(playlist.id, name);
              Navigator.pop(ctx);
            },
            child: const Text('Guardar')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = _ps.theme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      decoration: BoxDecoration(
        color: t.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.primary.withOpacity(0.15), width: 1)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              colors: [t.primary, t.primaryDark],
              begin: Alignment.topLeft, end: Alignment.bottomRight)),
          child: const Icon(Icons.queue_music_rounded, color: Colors.white, size: 26)),
        title: Text(playlist.name,
          style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold)),
        subtitle: Text('${playlist.songPaths.length} canciones',
          style: TextStyle(color: t.textSecondary, fontSize: 12)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            icon: Icon(Icons.play_circle_rounded, color: t.primary, size: 28),
            onPressed: () { _ps.playPlaylist(playlist, 0); _ps.setTab(1); }),
          PopupMenuButton<String>(
            color: t.isDark ? const Color(0xFF1E1E2E) : Colors.white,
            icon: Icon(Icons.more_vert_rounded, color: t.iconInactive),
            onSelected: (v) {
              if (v == 'rename') _showRenameDialog(context);
              if (v == 'delete') _ps.deletePlaylist(playlist.id);
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'rename',
                child: Row(children: [
                  Icon(Icons.edit_rounded, size: 18, color: t.textPrimary),
                  const SizedBox(width: 8),
                  Text('Renombrar', style: TextStyle(color: t.textPrimary))])),
              const PopupMenuItem(value: 'delete',
                child: Row(children: [
                  Icon(Icons.delete_rounded, size: 18, color: Colors.redAccent),
                  SizedBox(width: 8),
                  Text('Eliminar', style: TextStyle(color: Colors.redAccent))])),
            ],
          ),
        ]),
        onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => PlaylistDetailScreen(playlist: playlist))),
      ),
    );
  }
}

// ───────────────────────────────────────────────
// DETALLE PLAYLIST
// ───────────────────────────────────────────────
class PlaylistDetailScreen extends StatelessWidget {
  final PlaylistModel playlist;
  const PlaylistDetailScreen({super.key, required this.playlist});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _ps,
    builder: (ctx, __) {
      final t     = _ps.theme;
      final songs = playlist.songPaths.map((path) =>
        _ps.songs.firstWhere((s) => s.path == path,
          orElse: () => SongModel(
            path: path,
            title: path.split(Platform.pathSeparator).last,
            artist: ''))).toList();

      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: t.bgGradient)),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent, elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_rounded, color: t.textPrimary),
              onPressed: () => Navigator.pop(ctx)),
            title: Text(playlist.name,
              style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold)),
            actions: [
              if (songs.isNotEmpty)
                IconButton(
                  icon: Icon(Icons.play_circle_rounded, color: t.primary, size: 30),
                  onPressed: () {
                    _ps.playPlaylist(playlist, 0);
                    _ps.setTab(1);
                    Navigator.pop(ctx);
                  }),
              const SizedBox(width: 8),
            ],
          ),
          body: songs.isEmpty
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.music_off_rounded, size: 72, color: t.textHint),
                const SizedBox(height: 16),
                Text('Lista vacía', style: TextStyle(color: t.textSecondary, fontSize: 18)),
              ]))
            : ReorderableListView.builder(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: songs.length,
                onReorder: (o, n) => _ps.reorderPlaylistSongs(playlist.id, o, n),
                itemBuilder: (_, i) {
                  final s  = songs[i];
                  final gi = _ps.songs.indexWhere((x) => x.path == s.path);
                  final isActive = gi >= 0 && _ps.currentIndex == gi;
                  return ListTile(
                    key: ValueKey('${s.path}_$i'),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    leading: Container(
                      width: 52, height: 52,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: isActive ? t.primary.withOpacity(0.2) : t.cardBg),
                      clipBehavior: Clip.antiAlias,
                      // CAMBIO 2 aplicado también en el detalle de playlist
                      child: s.imagePath != null
                          ? Image.file(File(s.imagePath!), fit: BoxFit.cover)
                          : isActive && _ps.isPlaying
                              ? Icon(Icons.graphic_eq_rounded, color: t.primary)
                              : Center(
                                  child: Text(
                                    s.title.isNotEmpty ? s.title[0].toUpperCase() : '?',
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: isActive ? t.primary : t.iconInactive,
                                    ),
                                  ),
                                ),
                    ),
                    title: Text(s.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color:      isActive ? t.primary      : t.textPrimary,
                        fontWeight: isActive ? FontWeight.bold : FontWeight.normal)),
                    subtitle: Text(s.artist,
                      style: TextStyle(color: t.textSecondary, fontSize: 12)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.drag_handle_rounded, color: t.iconInactive, size: 22),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => _ps.removeSongFromPlaylist(playlist.id, s.path),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle, color: Colors.white10),
                          child: const Icon(Icons.remove_circle_outline_rounded,
                            color: Colors.redAccent, size: 18))),
                    ]),
                    onTap: gi >= 0
                        ? () { _ps.playPlaylist(playlist, i); _ps.setTab(1); }
                        : null,
                  );
                },
              ),
        ),
      );
    },
  );
}

// ═══════════════════════════════════════════════════════════
// PANTALLA: NOW PLAYING
// ═══════════════════════════════════════════════════════════
class NowPlayingScreen extends StatelessWidget {
  const NowPlayingScreen({super.key});

  String _fmt(Duration d) =>
      '${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:'
      '${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _ps,
    builder: (ctx, _) {
      final t        = _ps.theme;
      final song     = _ps.currentSong;
      final progress = _ps.duration.inMilliseconds > 0
          ? (_ps.position.inMilliseconds / _ps.duration.inMilliseconds).clamp(0.0, 1.0)
          : 0.0;
      final hasImage = song?.imagePath != null;
      final ci       = _ps.currentIndex;

      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [

              // ── Carátula ───────────────────────────────────
              GestureDetector(
                onTap: ci >= 0 ? () => _ps.pickImageForSong(ci) : null,
                child: Stack(alignment: Alignment.center, children: [
                  Container(
                    width: 260, height: 260,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: t.cardBg,
                      boxShadow: [
                        BoxShadow(color: t.primary.withOpacity(0.3),
                          blurRadius: 50, spreadRadius: 5),
                        const BoxShadow(color: Colors.black54,
                          blurRadius: 20, offset: Offset(0, 12))]),
                    clipBehavior: Clip.antiAlias,
                    // CAMBIO 2 en NowPlaying: inicial grande si no hay imagen
                    child: hasImage
                        ? Image.file(File(song!.imagePath!), fit: BoxFit.cover)
                        : Center(
                            child: Text(
                              song != null && song.title.isNotEmpty
                                  ? song.title[0].toUpperCase()
                                  : '♪',
                              style: TextStyle(
                                fontSize: 96,
                                fontWeight: FontWeight.bold,
                                color: t.primary.withOpacity(0.4),
                              ),
                            ),
                          )),
                  if (!hasImage)
                    Container(
                      width: 260, height: 260,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: Colors.black26),
                      child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                        Icon(Icons.add_photo_alternate_outlined, size: 28, color: t.iconInactive),
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Text('Toca para agregar imagen',
                            style: TextStyle(color: t.iconInactive, fontSize: 11))),
                      ])),
                ]),
              ),

              const SizedBox(height: 32),

              // ── Título + favorito ──────────────────────────
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(song?.title ?? 'Sin canción seleccionada',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: t.textPrimary),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(song?.artist ?? '—',
                    style: TextStyle(color: t.textSecondary, fontSize: 14)),
                ])),
                if (ci >= 0)
                  GestureDetector(
                    onTap: () => _ps.toggleFavorite(ci),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: _ps.songs[ci].isFavorite
                            ? LinearGradient(
                                colors: [t.primary, t.primaryDark],
                                begin: Alignment.topLeft, end: Alignment.bottomRight)
                            : null,
                        color: _ps.songs[ci].isFavorite ? null : Colors.white10),
                      child: Icon(
                        _ps.songs[ci].isFavorite
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: _ps.songs[ci].isFavorite ? Colors.white : t.iconInactive,
                        size: 22))),
              ]),

              const SizedBox(height: 24),

              // ── Barra de progreso ──────────────────────────
              SliderTheme(
                data: SliderTheme.of(ctx).copyWith(
                  trackHeight: 4,
                  activeTrackColor:   t.primary,
                  inactiveTrackColor: t.isDark ? Colors.white10 : Colors.black12,
                  thumbColor:         t.isDark ? Colors.white : t.primaryDark,
                  thumbShape:  const RoundSliderThumbShape(enabledThumbRadius: 7),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                  overlayColor: t.primary.withOpacity(0.2)),
                child: Slider(
                  value: progress as double,
                  onChanged: song == null ? null : (v) => _ps.seekTo(
                    Duration(milliseconds: (v * _ps.duration.inMilliseconds).round()))),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(_fmt(_ps.position),
                    style: TextStyle(color: t.textSecondary, fontSize: 11)),
                  Text(_fmt(_ps.duration),
                    style: TextStyle(color: t.textSecondary, fontSize: 11)),
                ]),
              ),

              const SizedBox(height: 24),

              // ── Controles ──────────────────────────────────
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                IconButton(
                  icon: Icon(Icons.shuffle_rounded,
                    color: _ps.shuffle ? t.primary : t.iconInactive),
                  onPressed: _ps.toggleShuffle),
                IconButton(iconSize: 40,
                  icon: Icon(Icons.skip_previous_rounded, color: t.textPrimary),
                  onPressed: _ps.prev),
                GestureDetector(
                  onTap: _ps.togglePlayPause,
                  child: Container(
                    width: 68, height: 68,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [t.primary, t.primaryDark],
                        begin: Alignment.topLeft, end: Alignment.bottomRight),
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(
                        color: t.primary.withOpacity(0.4),
                        blurRadius: 24, spreadRadius: 4)]),
                    child: Icon(
                      _ps.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: Colors.white, size: 40))),
                IconButton(iconSize: 40,
                  icon: Icon(Icons.skip_next_rounded, color: t.textPrimary),
                  onPressed: _ps.next),
                IconButton(
                  icon: Icon(Icons.repeat_rounded,
                    color: _ps.repeat ? t.primary : t.iconInactive),
                  onPressed: _ps.toggleRepeat),
              ]),
            ]),
          ),
        ),
      );
    },
  );
}

// ═══════════════════════════════════════════════════════════
// PANTALLA: DESCARGADOR
// ═══════════════════════════════════════════════════════════
enum _DlStatus { waiting, downloading, done, error }

class _DownloadItem {
  final String url;
  String    title;
  _DlStatus status;
  double    progress;
  String    message;
  String?   savedPath;

  _DownloadItem({required this.url})
      : title    = _shortUrl(url),
        status   = _DlStatus.waiting,
        progress = 0,
        message  = '';

  static String _shortUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.queryParameters['v'] ?? uri.host;
    } catch (_) { return url; }
  }
}

class DownloadScreen extends StatefulWidget {
  const DownloadScreen({super.key});
  @override
  State<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends State<DownloadScreen> {
  final _urlCtrl = TextEditingController();
  final _dirCtrl = TextEditingController();
  final List<_DownloadItem> _downloads = [];

  @override
  void dispose() { _urlCtrl.dispose(); _dirCtrl.dispose(); super.dispose(); }

  Future<void> _pickFolder() async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path != null) setState(() => _dirCtrl.text = path);
  }

  Future<void> _startDownload() async {
    final url = _urlCtrl.text.trim();
    final dir = _dirCtrl.text.trim();
    if (url.isEmpty) { _snack('Pega un enlace de YouTube primero'); return; }
    if (dir.isEmpty) { _snack('Selecciona una carpeta de destino'); return; }

    final item = _DownloadItem(url: url);
    setState(() { _downloads.insert(0, item); _urlCtrl.clear(); });

    // CAMBIO 3: Busca yt-dlp y si no lo encuentra lo descarga automáticamente.
    final ytdlp = await _findOrDownloadYtDlp(item);
    if (ytdlp == null) {
      setState(() {
        item.status  = _DlStatus.error;
        item.message = 'No se pudo obtener yt-dlp. Verifica tu conexión a internet.';
      });
      return;
    }

    setState(() => item.status = _DlStatus.downloading);

    try {
      final proc = await Process.start(ytdlp, [
        '-x', '--audio-format', 'mp3', '--audio-quality', '0',
        '-o', '$dir${Platform.pathSeparator}%(title)s.%(ext)s',
        '--no-playlist', '--print', 'after_move:filepath',
        url,
      ], runInShell: true);

      String? finalPath;
      final buf = StringBuffer();

      proc.stdout.transform(const SystemEncoding().decoder).listen((line) {
        buf.write(line);
        final m = RegExp(r'\[download\] Destination: .+[/\\](.+)\.').firstMatch(line);
        if (m != null) setState(() => item.title = m.group(1) ?? item.title);
        final pct = RegExp(r'(\d+\.?\d*)%').firstMatch(line);
        if (pct != null) setState(() =>
          item.progress = double.tryParse(pct.group(1) ?? '0') ?? 0);
        final trimmed = line.trim();
        if (trimmed.endsWith('.mp3') || trimmed.endsWith('.m4a')) finalPath = trimmed;
      });

      proc.stderr.transform(const SystemEncoding().decoder).listen(buf.write);
      final exit = await proc.exitCode;

      if (exit == 0) {
        setState(() {
          item.status   = _DlStatus.done;
          item.progress = 100;
          item.message  = 'Guardado en $dir';
          if (finalPath != null) item.savedPath = finalPath;
        });
        if (finalPath != null) _ps.addDownloadedSong(finalPath!);
      } else {
        setState(() {
          item.status  = _DlStatus.error;
          item.message = buf.toString().split('\n')
              .lastWhere((l) => l.trim().isNotEmpty, orElse: () => 'Error desconocido');
        });
      }
    } catch (e) {
      setState(() { item.status = _DlStatus.error; item.message = e.toString(); });
    }
  }

  // CAMBIO 3: Primero busca yt-dlp instalado, si no lo encuentra
  // lo descarga automáticamente desde GitHub en la carpeta de datos de la app.
  Future<String?> _findOrDownloadYtDlp(_DownloadItem item) async {
    // 1. Buscar en PATH y rutas conocidas de Windows
    final found = await _findYtDlp();
    if (found != null) return found;

    // 2. Verificar si ya fue descargado antes por la app
    final appDir = (await getApplicationSupportDirectory()).path;
    final localPath = '$appDir${Platform.pathSeparator}yt-dlp.exe';
    if (await File(localPath).exists()) return localPath;

    // 3. Descargarlo automáticamente desde la release oficial de GitHub
    setState(() => item.message = 'Descargando yt-dlp automáticamente...');
    try {
      final response = await http.get(Uri.parse(
        'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe',
      ));
      if (response.statusCode == 200) {
        await File(localPath).writeAsBytes(response.bodyBytes);
        setState(() => item.message = 'yt-dlp listo. Iniciando descarga...');
        return localPath;
      }
    } catch (_) {}

    return null;
  }

  Future<String?> _findYtDlp() async {
    for (final cmd in ['yt-dlp', 'yt-dlp.exe']) {
      try {
        final r = await Process.run('where', [cmd], runInShell: true);
        if (r.exitCode == 0) {
          final p = (r.stdout as String).trim().split('\n').first.trim();
          if (p.isNotEmpty) return p;
        }
      } catch (_) {}
    }
    for (final p in [
      r'C:\yt-dlp\yt-dlp.exe',
      r'C:\Program Files\yt-dlp\yt-dlp.exe',
      '${Platform.environment['USERPROFILE']}\\yt-dlp\\yt-dlp.exe',
      '${Platform.environment['APPDATA']}\\yt-dlp\\yt-dlp.exe',
    ]) { if (await File(p).exists()) return p; }
    return null;
  }

  Future<void> _pasteClipboard() async {
    try {
      final r = await Process.run('powershell', ['-command', 'Get-Clipboard'], runInShell: true);
      final text = (r.stdout as String).trim();
      if (text.isNotEmpty) setState(() => _urlCtrl.text = text);
    } catch (_) {}
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));

  @override
  Widget build(BuildContext context) {
    final t = _ps.theme;
    return Column(children: [
      // ── Header ─────────────────────────────────────────
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 48, 20, 8),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [t.primary, t.primaryDark],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.download_rounded, color: Colors.white, size: 26)),
          const SizedBox(width: 14),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Descargar música', style: TextStyle(
              fontSize: 22, fontWeight: FontWeight.bold, color: t.textPrimary)),
            Text('Descarga MP3 desde YouTube',
              style: TextStyle(color: t.textSecondary, fontSize: 12)),
          ]),
        ]),
      ),

      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // ── URL ──
            Text('Enlace de YouTube',
              style: TextStyle(color: t.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _urlCtrl,
                  style: TextStyle(color: t.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'https://youtube.com/watch?v=...',
                    hintStyle: TextStyle(color: t.textHint, fontSize: 13),
                    prefixIcon: Icon(Icons.link_rounded, color: t.iconInactive),
                    filled: true, fillColor: t.cardBg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: t.primary, width: 1.5)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
                  onSubmitted: (_) => _startDownload()),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _pasteClipboard,
                child: Tooltip(
                  message: 'Pegar URL',
                  child: Container(
                    width: 50, height: 50,
                    decoration: BoxDecoration(
                      color: t.cardBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: t.primary.withOpacity(0.3), width: 1.5)),
                    child: Icon(Icons.content_paste_rounded, color: t.primary, size: 22)))),
            ]),

            const SizedBox(height: 18),

            // ── Carpeta destino ──
            Text('Guardar en',
              style: TextStyle(color: t.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _dirCtrl, readOnly: true,
                  style: TextStyle(color: t.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Selecciona carpeta de destino...',
                    hintStyle: TextStyle(color: t.textHint, fontSize: 13),
                    prefixIcon: Icon(Icons.folder_rounded, color: t.iconInactive),
                    filled: true, fillColor: t.cardBg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14))),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _pickFolder,
                child: Tooltip(
                  message: 'Elegir carpeta',
                  child: Container(
                    width: 50, height: 50,
                    decoration: BoxDecoration(
                      color: t.cardBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: t.primary.withOpacity(0.3), width: 1.5)),
                    child: Icon(Icons.folder_open_rounded, color: t.primary, size: 22)))),
            ]),

            const SizedBox(height: 24),

            // ── Botón descargar ──
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: t.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                onPressed: _startDownload,
                icon: const Icon(Icons.download_rounded, size: 22),
                label: const Text('Descargar MP3',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)))),

            const SizedBox(height: 6),
            // CAMBIO 3: Actualizado el texto informativo — ya no requiere instalación manual
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.info_outline_rounded, size: 13, color: t.textHint),
              const SizedBox(width: 4),
              Text('yt-dlp se descarga automáticamente si es necesario',
                style: TextStyle(color: t.textHint, fontSize: 11)),
            ]),

            // ── Lista de descargas ──
            if (_downloads.isNotEmpty) ...[
              const SizedBox(height: 28),
              Text('Descargas', style: TextStyle(
                color: t.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              ..._downloads.map((item) => _DlTile(item: item, t: t)),
            ],
          ]),
        ),
      ),
    ]);
  }
}

// ───────────────────────────────────────────────
// TILE DESCARGA
// ───────────────────────────────────────────────
class _DlTile extends StatelessWidget {
  final _DownloadItem item;
  final AppTheme      t;
  const _DlTile({required this.item, required this.t});

  @override
  Widget build(BuildContext context) {
    final color = item.status == _DlStatus.done
        ? Colors.greenAccent
        : item.status == _DlStatus.error
            ? Colors.redAccent
            : t.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.25), width: 1)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(
            item.status == _DlStatus.done        ? Icons.check_circle_rounded  :
            item.status == _DlStatus.error       ? Icons.error_rounded         :
            item.status == _DlStatus.downloading ? Icons.downloading_rounded   :
                                                   Icons.hourglass_top_rounded,
            color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(item.title,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: t.textPrimary,
                fontWeight: FontWeight.w600, fontSize: 13))),
          Text(
            item.status == _DlStatus.done        ? '✓ Listo'   :
            item.status == _DlStatus.error       ? 'Error'     :
            item.status == _DlStatus.downloading
                ? '${item.progress.toStringAsFixed(0)}%' : 'Esperando...',
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
        ]),
        if (item.status == _DlStatus.downloading) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: item.progress / 100,
              backgroundColor: t.isDark ? Colors.white10 : Colors.black12,
              valueColor: AlwaysStoppedAnimation<Color>(t.primary),
              minHeight: 5)),
        ],
        if (item.message.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(item.message,
            maxLines: 2, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: t.textSecondary, fontSize: 11)),
        ],
      ]),
    );
  }
}