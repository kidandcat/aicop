require 'sinatra'
require 'json'
require 'sqlite3'
require 'jwt'
require 'bcrypt'

JWT_SECRET = 'booking-api-secret-key-2026'

set :port, 8080
set :bind, '0.0.0.0'
set :server, :puma
set :logging, false

# --- Database Setup ---

WORKDIR = ENV['WORKDIR'] || '.'
DB_PATH = File.join(WORKDIR, 'booking.db')
SCHEMA_PATH = File.join(WORKDIR, 'schema.sql')

db = SQLite3::Database.new(DB_PATH)
db.execute('PRAGMA journal_mode=WAL')
db.execute('PRAGMA busy_timeout=5000')
db.execute('PRAGMA foreign_keys=ON')
db.results_as_hash = true

schema = File.read(SCHEMA_PATH)
db.execute_batch(schema)

DB = db

# --- Helpers ---

def json_response(status_code, body)
  content_type :json
  status status_code
  body.to_json
end

def parse_json_body
  begin
    body = request.body.read
    return {} if body.nil? || body.empty?
    JSON.parse(body)
  rescue JSON::ParserError
    {}
  end
end

def generate_token(user_id)
  payload = {
    'user_id' => user_id,
    'exp' => Time.now.to_i + 86400
  }
  JWT.encode(payload, JWT_SECRET, 'HS256')
end

def authenticate!
  auth_header = request.env['HTTP_AUTHORIZATION']
  if auth_header.nil? || !auth_header.start_with?('Bearer ')
    halt 401, { 'Content-Type' => 'application/json' }, { error: 'unauthorized' }.to_json
  end

  token = auth_header.sub('Bearer ', '')
  begin
    decoded = JWT.decode(token, JWT_SECRET, true, { algorithm: 'HS256' })
    claims = decoded[0]
    user_id = claims['user_id']
    if user_id.nil?
      halt 401, { 'Content-Type' => 'application/json' }, { error: 'unauthorized' }.to_json
    end
    user_id.to_i
  rescue JWT::DecodeError, JWT::ExpiredSignature
    halt 401, { 'Content-Type' => 'application/json' }, { error: 'unauthorized' }.to_json
  end
end

# --- Auth Routes ---

post '/api/auth/register' do
  params = parse_json_body
  email = params['email']
  name = params['name']
  password = params['password']

  if email.nil? || email.empty? || name.nil? || name.empty? || password.nil? || password.empty?
    return json_response(400, { error: 'missing required fields' })
  end

  password_hash = BCrypt::Password.create(password)

  begin
    DB.execute('INSERT INTO users (email, name, password_hash) VALUES (?, ?, ?)', [email, name, password_hash])
    id = DB.last_insert_row_id
    json_response(201, { id: id, email: email, name: name })
  rescue SQLite3::ConstraintException => e
    if e.message.include?('UNIQUE')
      json_response(409, { error: 'email already exists' })
    else
      json_response(500, { error: 'internal error' })
    end
  end
end

post '/api/auth/login' do
  params = parse_json_body
  email = params['email']
  password = params['password']

  row = DB.get_first_row('SELECT id, name, password_hash FROM users WHERE email = ?', [email])
  if row.nil?
    return json_response(401, { error: 'invalid credentials' })
  end

  stored_hash = row['password_hash']
  begin
    unless BCrypt::Password.new(stored_hash) == password
      return json_response(401, { error: 'invalid credentials' })
    end
  rescue BCrypt::Errors::InvalidHash
    return json_response(401, { error: 'invalid credentials' })
  end

  token = generate_token(row['id'])
  json_response(200, {
    token: token,
    user: {
      id: row['id'],
      email: email,
      name: row['name']
    }
  })
end

# --- Space Routes ---

get '/api/spaces' do
  query = 'SELECT id, name, description, price_per_hour, owner_id, created_at FROM spaces WHERE 1=1'
  args = []

  if params['min_price'] && !params['min_price'].empty?
    begin
      min_p = Float(params['min_price'])
      query += ' AND price_per_hour >= ?'
      args << min_p
    rescue ArgumentError
      # ignore invalid value
    end
  end

  if params['max_price'] && !params['max_price'].empty?
    begin
      max_p = Float(params['max_price'])
      query += ' AND price_per_hour <= ?'
      args << max_p
    rescue ArgumentError
      # ignore invalid value
    end
  end

  if params['available_at'] && !params['available_at'].empty?
    query += " AND id NOT IN (SELECT space_id FROM bookings WHERE status IN ('pending','confirmed') AND start_time < ? AND ? < end_time)"
    args << params['available_at']
    args << params['available_at']
  end

  rows = DB.execute(query, args)
  spaces = rows.map do |row|
    {
      id: row['id'],
      name: row['name'],
      description: row['description'] || '',
      price_per_hour: row['price_per_hour'],
      owner_id: row['owner_id'],
      created_at: row['created_at']
    }
  end

  json_response(200, spaces)
end

post '/api/spaces' do
  user_id = authenticate!
  params = parse_json_body
  name = params['name']
  description = params['description'] || ''
  price_per_hour = params['price_per_hour']

  if name.nil? || name.empty? || price_per_hour.nil? || price_per_hour == 0
    return json_response(400, { error: 'missing required fields' })
  end

  DB.execute('INSERT INTO spaces (name, description, price_per_hour, owner_id) VALUES (?, ?, ?, ?)',
             [name, description, price_per_hour, user_id])
  id = DB.last_insert_row_id

  row = DB.get_first_row('SELECT created_at FROM spaces WHERE id = ?', [id])
  created_at = row ? row['created_at'] : ''

  json_response(201, {
    id: id,
    name: name,
    description: description,
    price_per_hour: price_per_hour,
    owner_id: user_id,
    created_at: created_at
  })
end

# --- Booking Routes ---

get '/api/bookings/my' do
  user_id = authenticate!

  rows = DB.execute('SELECT id, space_id, user_id, start_time, end_time, status, created_at FROM bookings WHERE user_id = ?', [user_id])
  bookings = rows.map do |row|
    {
      id: row['id'],
      space_id: row['space_id'],
      user_id: row['user_id'],
      start_time: row['start_time'],
      end_time: row['end_time'],
      status: row['status'],
      created_at: row['created_at']
    }
  end

  json_response(200, bookings)
end

post '/api/bookings' do
  user_id = authenticate!
  params = parse_json_body
  space_id = params['space_id']
  start_time = params['start_time']
  end_time = params['end_time']

  if space_id.nil? || space_id == 0 || start_time.nil? || start_time.empty? || end_time.nil? || end_time.empty?
    return json_response(400, { error: 'missing required fields' })
  end

  # Check space exists
  count_row = DB.get_first_row('SELECT COUNT(*) as cnt FROM spaces WHERE id = ?', [space_id])
  if count_row.nil? || count_row['cnt'] == 0
    return json_response(404, { error: 'space not found' })
  end

  # Check overlap
  overlap_row = DB.get_first_row(
    "SELECT COUNT(*) as cnt FROM bookings WHERE space_id = ? AND status IN ('pending','confirmed') AND start_time < ? AND ? < end_time",
    [space_id, end_time, start_time]
  )
  if overlap_row && overlap_row['cnt'] > 0
    return json_response(409, { error: 'booking overlap' })
  end

  DB.execute(
    "INSERT INTO bookings (space_id, user_id, start_time, end_time, status) VALUES (?, ?, ?, ?, 'confirmed')",
    [space_id, user_id, start_time, end_time]
  )
  id = DB.last_insert_row_id

  row = DB.get_first_row('SELECT created_at FROM bookings WHERE id = ?', [id])
  created_at = row ? row['created_at'] : ''

  json_response(201, {
    id: id,
    space_id: space_id,
    user_id: user_id,
    start_time: start_time,
    end_time: end_time,
    status: 'confirmed',
    created_at: created_at
  })
end

delete '/api/bookings/:id' do
  user_id = authenticate!

  booking_id = params['id'].to_i
  if booking_id == 0
    return json_response(404, { error: 'booking not found' })
  end

  row = DB.get_first_row(
    'SELECT id, space_id, user_id, start_time, end_time, status, created_at FROM bookings WHERE id = ?',
    [booking_id]
  )
  if row.nil?
    return json_response(404, { error: 'booking not found' })
  end

  if row['user_id'] != user_id
    return json_response(403, { error: 'forbidden' })
  end

  DB.execute("UPDATE bookings SET status = 'cancelled' WHERE id = ?", [booking_id])

  json_response(200, {
    id: row['id'],
    space_id: row['space_id'],
    user_id: row['user_id'],
    start_time: row['start_time'],
    end_time: row['end_time'],
    status: 'cancelled',
    created_at: row['created_at']
  })
end
