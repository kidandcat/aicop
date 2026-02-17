import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:sqlite3/sqlite3.dart';

const jwtSecret = 'booking-api-secret-key-2026';

// ---------------------------------------------------------------------------
// Database
// ---------------------------------------------------------------------------

late Database db;

void initDb() {
  final dbPath = '${Directory.current.path}/booking.db';
  final schemaPath = '${Directory.current.path}/schema.sql';

  db = sqlite3.open(dbPath);
  db.execute('PRAGMA journal_mode=WAL');
  db.execute('PRAGMA foreign_keys=ON');

  final schema = File(schemaPath).readAsStringSync();
  // Split on semicolons and execute each statement
  for (final stmt in schema.split(';')) {
    final trimmed = stmt.trim();
    if (trimmed.isNotEmpty) {
      db.execute('$trimmed;');
    }
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String hashPassword(String password) {
  // SHA-256 with a static salt (meets minimum requirement)
  final bytes = utf8.encode('booking-salt:$password');
  return sha256.convert(bytes).toString();
}

bool verifyPassword(String password, String hash) {
  return hashPassword(password) == hash;
}

String generateToken(int userId) {
  final jwt = JWT({'user_id': userId});
  return jwt.sign(SecretKey(jwtSecret));
}

int? extractUserId(shelf.Request request) {
  final authHeader = request.headers['authorization'];
  if (authHeader == null || !authHeader.startsWith('Bearer ')) return null;
  final token = authHeader.substring(7);
  try {
    final jwt = JWT.verify(token, SecretKey(jwtSecret));
    final payload = jwt.payload as Map<String, dynamic>;
    return payload['user_id'] as int;
  } catch (_) {
    return null;
  }
}

shelf.Response jsonResponse(int status, Object body) {
  return shelf.Response(
    status,
    body: jsonEncode(body),
    headers: {'content-type': 'application/json'},
  );
}

shelf.Response unauthorized() =>
    jsonResponse(401, {'error': 'unauthorized'});

// ---------------------------------------------------------------------------
// Auth endpoints
// ---------------------------------------------------------------------------

shelf.Response handleRegister(shelf.Request request, String body) {
  final data = jsonDecode(body) as Map<String, dynamic>;

  final email = data['email'];
  final name = data['name'];
  final password = data['password'];

  if (email == null || name == null || password == null ||
      (email as String).isEmpty ||
      (name as String).isEmpty ||
      (password as String).isEmpty) {
    return jsonResponse(400, {'error': 'missing required fields'});
  }

  // Check duplicate email
  final existing = db.select('SELECT id FROM users WHERE email = ?', [email]);
  if (existing.isNotEmpty) {
    return jsonResponse(409, {'error': 'email already exists'});
  }

  final hash = hashPassword(password);
  db.execute(
    'INSERT INTO users (email, name, password_hash) VALUES (?, ?, ?)',
    [email, name, hash],
  );
  final id = db.lastInsertRowId;

  return jsonResponse(201, {
    'id': id,
    'email': email,
    'name': name,
  });
}

shelf.Response handleLogin(shelf.Request request, String body) {
  final data = jsonDecode(body) as Map<String, dynamic>;

  final email = data['email'];
  final password = data['password'];

  if (email == null || password == null) {
    return jsonResponse(400, {'error': 'missing required fields'});
  }

  final rows = db.select(
    'SELECT id, email, name, password_hash FROM users WHERE email = ?',
    [email],
  );

  if (rows.isEmpty) {
    return jsonResponse(401, {'error': 'invalid credentials'});
  }

  final user = rows.first;
  if (!verifyPassword(password as String, user['password_hash'] as String)) {
    return jsonResponse(401, {'error': 'invalid credentials'});
  }

  final userId = user['id'] as int;
  final token = generateToken(userId);

  return jsonResponse(200, {
    'token': token,
    'user': {
      'id': userId,
      'email': user['email'],
      'name': user['name'],
    },
  });
}

// ---------------------------------------------------------------------------
// Spaces endpoints
// ---------------------------------------------------------------------------

shelf.Response handleListSpaces(shelf.Request request) {
  final params = request.requestedUri.queryParameters;

  var query = 'SELECT * FROM spaces WHERE 1=1';
  final args = <Object?>[];

  if (params.containsKey('min_price')) {
    query += ' AND price_per_hour >= ?';
    args.add(double.parse(params['min_price']!));
  }
  if (params.containsKey('max_price')) {
    query += ' AND price_per_hour <= ?';
    args.add(double.parse(params['max_price']!));
  }
  if (params.containsKey('available_at')) {
    final at = params['available_at']!;
    query += ''' AND id NOT IN (
      SELECT space_id FROM bookings
      WHERE status IN ('pending','confirmed')
        AND start_time < ? AND end_time > ?
    )''';
    args.addAll([at, at]);
  }

  final rows = db.select(query, args);
  final spaces = rows.map((r) => _spaceMap(r)).toList();
  return jsonResponse(200, spaces);
}

shelf.Response handleCreateSpace(shelf.Request request, String body) {
  final userId = extractUserId(request);
  if (userId == null) return unauthorized();

  final data = jsonDecode(body) as Map<String, dynamic>;
  final name = data['name'];
  final pricePerHour = data['price_per_hour'];

  if (name == null || pricePerHour == null ||
      (name as String).isEmpty) {
    return jsonResponse(400, {'error': 'missing required fields'});
  }

  final description = data['description'] as String? ?? '';

  db.execute(
    'INSERT INTO spaces (name, description, price_per_hour, owner_id) VALUES (?, ?, ?, ?)',
    [name, description, (pricePerHour as num).toDouble(), userId],
  );
  final id = db.lastInsertRowId;

  final rows = db.select('SELECT * FROM spaces WHERE id = ?', [id]);
  return jsonResponse(201, _spaceMap(rows.first));
}

Map<String, dynamic> _spaceMap(Row r) => {
  'id': r['id'],
  'name': r['name'],
  'description': r['description'] ?? '',
  'price_per_hour': (r['price_per_hour'] as num).toDouble(),
  'owner_id': r['owner_id'],
  'created_at': r['created_at'],
};

// ---------------------------------------------------------------------------
// Bookings endpoints
// ---------------------------------------------------------------------------

shelf.Response handleCreateBooking(shelf.Request request, String body) {
  final userId = extractUserId(request);
  if (userId == null) return unauthorized();

  final data = jsonDecode(body) as Map<String, dynamic>;
  final spaceId = data['space_id'];
  final startTime = data['start_time'];
  final endTime = data['end_time'];

  if (spaceId == null || startTime == null || endTime == null) {
    return jsonResponse(400, {'error': 'missing required fields'});
  }

  // Check space exists
  final spaceRows = db.select('SELECT id FROM spaces WHERE id = ?', [spaceId]);
  if (spaceRows.isEmpty) {
    return jsonResponse(404, {'error': 'space not found'});
  }

  // Check overlap
  final overlaps = db.select('''
    SELECT id FROM bookings
    WHERE space_id = ?
      AND status IN ('pending','confirmed')
      AND start_time < ? AND end_time > ?
  ''', [spaceId, endTime, startTime]);

  if (overlaps.isNotEmpty) {
    return jsonResponse(409, {'error': 'booking overlap'});
  }

  db.execute(
    "INSERT INTO bookings (space_id, user_id, start_time, end_time, status) VALUES (?, ?, ?, ?, 'confirmed')",
    [spaceId, userId, startTime, endTime],
  );
  final id = db.lastInsertRowId;

  final rows = db.select('SELECT * FROM bookings WHERE id = ?', [id]);
  return jsonResponse(201, _bookingMap(rows.first));
}

shelf.Response handleMyBookings(shelf.Request request) {
  final userId = extractUserId(request);
  if (userId == null) return unauthorized();

  final rows = db.select(
    'SELECT * FROM bookings WHERE user_id = ?',
    [userId],
  );
  final bookings = rows.map((r) => _bookingMap(r)).toList();
  return jsonResponse(200, bookings);
}

shelf.Response handleCancelBooking(shelf.Request request, String idStr) {
  final userId = extractUserId(request);
  if (userId == null) return unauthorized();

  final bookingId = int.tryParse(idStr);
  if (bookingId == null) {
    return jsonResponse(404, {'error': 'booking not found'});
  }

  final rows = db.select('SELECT * FROM bookings WHERE id = ?', [bookingId]);
  if (rows.isEmpty) {
    return jsonResponse(404, {'error': 'booking not found'});
  }

  final booking = rows.first;
  if (booking['user_id'] as int != userId) {
    return jsonResponse(403, {'error': 'forbidden'});
  }

  db.execute(
    "UPDATE bookings SET status = 'cancelled' WHERE id = ?",
    [bookingId],
  );

  final updated = db.select('SELECT * FROM bookings WHERE id = ?', [bookingId]);
  return jsonResponse(200, _bookingMap(updated.first));
}

Map<String, dynamic> _bookingMap(Row r) => {
  'id': r['id'],
  'space_id': r['space_id'],
  'user_id': r['user_id'],
  'start_time': r['start_time'],
  'end_time': r['end_time'],
  'status': r['status'],
  'created_at': r['created_at'],
};

// ---------------------------------------------------------------------------
// Router setup
// ---------------------------------------------------------------------------

Future<shelf.Response> _readBody(
  shelf.Request request,
  shelf.Response Function(shelf.Request, String) handler,
) async {
  final body = await request.readAsString();
  return handler(request, body);
}

shelf.Handler buildApp() {
  final router = Router();

  // Auth
  router.post('/api/auth/register', (shelf.Request r) => _readBody(r, handleRegister));
  router.post('/api/auth/login', (shelf.Request r) => _readBody(r, handleLogin));

  // Spaces
  router.get('/api/spaces', handleListSpaces);
  router.post('/api/spaces', (shelf.Request r) => _readBody(r, handleCreateSpace));

  // Bookings
  router.get('/api/bookings/my', handleMyBookings);
  router.post('/api/bookings', (shelf.Request r) => _readBody(r, handleCreateBooking));
  router.delete('/api/bookings/<id>', (shelf.Request r, String id) => handleCancelBooking(r, id));

  return router.call;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

void main() async {
  initDb();

  final handler = const shelf.Pipeline()
      .addMiddleware(shelf.logRequests())
      .addHandler(buildApp());

  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, 8080);
  print('Server listening on port ${server.port}');
}
