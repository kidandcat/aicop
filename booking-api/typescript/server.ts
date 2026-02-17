import express, { Request, Response, NextFunction } from 'express';
import Database from 'better-sqlite3';
import jwt from 'jsonwebtoken';
import bcrypt from 'bcryptjs';
import fs from 'fs';
import path from 'path';

const JWT_SECRET = 'booking-api-secret-key';
const PORT = 8080;
const DB_PATH = path.join(__dirname, '..', 'booking.db');
const SCHEMA_PATH = path.join(__dirname, '..', 'schema.sql');

// Initialize database
const db = new Database(DB_PATH);
db.pragma('journal_mode = WAL');
db.pragma('foreign_keys = ON');

const schema = fs.readFileSync(SCHEMA_PATH, 'utf-8');
db.exec(schema);

const app = express();
app.use(express.json());

// Auth middleware
interface AuthRequest extends Request {
  userId?: number;
}

function authRequired(req: AuthRequest, res: Response, next: NextFunction): void {
  const header = req.headers.authorization;
  if (!header || !header.startsWith('Bearer ')) {
    res.status(401).json({ error: 'unauthorized' });
    return;
  }
  const token = header.slice(7);
  try {
    const payload = jwt.verify(token, JWT_SECRET) as { user_id: number };
    req.userId = payload.user_id;
    next();
  } catch {
    res.status(401).json({ error: 'unauthorized' });
  }
}

// POST /api/auth/register
app.post('/api/auth/register', (req: Request, res: Response) => {
  const { email, name, password } = req.body;
  if (!email || !name || !password) {
    res.status(400).json({ error: 'missing required fields' });
    return;
  }

  const hash = bcrypt.hashSync(password, 10);

  try {
    const result = db.prepare(
      'INSERT INTO users (email, name, password_hash) VALUES (?, ?, ?)'
    ).run(email, name, hash);

    const user = db.prepare('SELECT id, email, name FROM users WHERE id = ?').get(result.lastInsertRowid) as any;
    res.status(201).json(user);
  } catch (err: any) {
    if (err.message?.includes('UNIQUE constraint')) {
      res.status(409).json({ error: 'email already exists' });
    } else {
      res.status(500).json({ error: 'internal error' });
    }
  }
});

// POST /api/auth/login
app.post('/api/auth/login', (req: Request, res: Response) => {
  const { email, password } = req.body;
  if (!email || !password) {
    res.status(400).json({ error: 'missing required fields' });
    return;
  }

  const user = db.prepare('SELECT * FROM users WHERE email = ?').get(email) as any;
  if (!user || !bcrypt.compareSync(password, user.password_hash)) {
    res.status(401).json({ error: 'invalid credentials' });
    return;
  }

  const token = jwt.sign({ user_id: user.id }, JWT_SECRET);
  res.json({
    token,
    user: { id: user.id, email: user.email, name: user.name },
  });
});

// GET /api/spaces
app.get('/api/spaces', (req: Request, res: Response) => {
  let query = 'SELECT * FROM spaces WHERE 1=1';
  const params: any[] = [];

  if (req.query.min_price) {
    query += ' AND price_per_hour >= ?';
    params.push(Number(req.query.min_price));
  }
  if (req.query.max_price) {
    query += ' AND price_per_hour <= ?';
    params.push(Number(req.query.max_price));
  }
  if (req.query.available_at) {
    const at = req.query.available_at as string;
    query += ` AND id NOT IN (
      SELECT space_id FROM bookings
      WHERE status IN ('pending', 'confirmed')
        AND start_time < ? AND end_time > ?
    )`;
    params.push(at, at);
  }

  const spaces = db.prepare(query).all(...params);
  res.json(spaces);
});

// POST /api/spaces
app.post('/api/spaces', authRequired, (req: AuthRequest, res: Response) => {
  const { name, description, price_per_hour } = req.body;
  if (!name || price_per_hour == null) {
    res.status(400).json({ error: 'missing required fields' });
    return;
  }

  const result = db.prepare(
    'INSERT INTO spaces (name, description, price_per_hour, owner_id) VALUES (?, ?, ?, ?)'
  ).run(name, description || null, price_per_hour, req.userId!);

  const space = db.prepare('SELECT * FROM spaces WHERE id = ?').get(result.lastInsertRowid);
  res.status(201).json(space);
});

// GET /api/bookings/my
app.get('/api/bookings/my', authRequired, (req: AuthRequest, res: Response) => {
  const bookings = db.prepare('SELECT * FROM bookings WHERE user_id = ?').all(req.userId!);
  res.json(bookings);
});

// POST /api/bookings
app.post('/api/bookings', authRequired, (req: AuthRequest, res: Response) => {
  const { space_id, start_time, end_time } = req.body;
  if (!space_id || !start_time || !end_time) {
    res.status(400).json({ error: 'missing required fields' });
    return;
  }

  const space = db.prepare('SELECT id FROM spaces WHERE id = ?').get(space_id);
  if (!space) {
    res.status(404).json({ error: 'space not found' });
    return;
  }

  const overlap = db.prepare(
    `SELECT id FROM bookings
     WHERE space_id = ? AND status IN ('pending', 'confirmed')
       AND start_time < ? AND end_time > ?`
  ).get(space_id, end_time, start_time);

  if (overlap) {
    res.status(409).json({ error: 'booking overlap' });
    return;
  }

  const result = db.prepare(
    `INSERT INTO bookings (space_id, user_id, start_time, end_time, status)
     VALUES (?, ?, ?, ?, 'confirmed')`
  ).run(space_id, req.userId!, start_time, end_time);

  const booking = db.prepare('SELECT * FROM bookings WHERE id = ?').get(result.lastInsertRowid);
  res.status(201).json(booking);
});

// DELETE /api/bookings/:id
app.delete('/api/bookings/:id', authRequired, (req: AuthRequest, res: Response) => {
  const bookingId = Number(req.params.id);
  const booking = db.prepare('SELECT * FROM bookings WHERE id = ?').get(bookingId) as any;

  if (!booking) {
    res.status(404).json({ error: 'booking not found' });
    return;
  }

  if (booking.user_id !== req.userId) {
    res.status(403).json({ error: 'forbidden' });
    return;
  }

  db.prepare("UPDATE bookings SET status = 'cancelled' WHERE id = ?").run(bookingId);
  const updated = db.prepare('SELECT * FROM bookings WHERE id = ?').get(bookingId);
  res.json(updated);
});

app.listen(PORT, () => {
  console.log(`Booking API listening on port ${PORT}`);
});
