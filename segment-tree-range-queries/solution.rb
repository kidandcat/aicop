# Segment Tree - Range Sum Queries with Point Updates
#
# Approach:
#   - Build a recursive segment tree stored in a 1-indexed array of size 4*N.
#   - Node v covers the segment [tl, tr].
#   - Left child = 2*v, right child = 2*v+1.
#   - Each node stores the sum of its segment.
#   - Update: traverse to the leaf and propagate sums back up -> O(log N).
#   - Query: split the range across children recursively -> O(log N).
#
# Uses $stdin for reading input.
# Ruby integers are arbitrary precision, so 64-bit overflow is not a concern.

def main
  n, q = $stdin.gets.split.map(&:to_i)
  a = $stdin.gets.split.map(&:to_i)

  # Segment tree array, 1-indexed, size 4*n
  tree = Array.new(4 * n, 0)

  # Build the segment tree recursively from array a.
  # v = current node index, tl..tr = segment covered by node v (0-indexed).
  build = lambda do |v, tl, tr|
    if tl == tr
      tree[v] = a[tl]
      return
    end
    tm = (tl + tr) / 2
    build.call(2 * v, tl, tm)
    build.call(2 * v + 1, tm + 1, tr)
    tree[v] = tree[2 * v] + tree[2 * v + 1]
  end

  # Update position pos to value val, propagate sums upward.
  update = lambda do |v, tl, tr, pos, val|
    if tl == tr
      tree[v] = val
      return
    end
    tm = (tl + tr) / 2
    if pos <= tm
      update.call(2 * v, tl, tm, pos, val)
    else
      update.call(2 * v + 1, tm + 1, tr, pos, val)
    end
    tree[v] = tree[2 * v] + tree[2 * v + 1]
  end

  # Query the sum of elements in range [l, r] (0-indexed).
  query = lambda do |v, tl, tr, l, r|
    return 0 if l > r
    return tree[v] if l == tl && r == tr
    tm = (tl + tr) / 2
    left_sum = query.call(2 * v, tl, tm, l, [r, tm].min)
    right_sum = query.call(2 * v + 1, tm + 1, tr, [l, tm + 1].max, r)
    left_sum + right_sum
  end

  # Build the tree over 0-indexed array positions [0, n-1]
  build.call(1, 0, n - 1)

  output = []
  q.times do
    parts = $stdin.gets.split.map(&:to_i)
    if parts[0] == 1
      # Update: position i (1-indexed) -> convert to 0-indexed
      i = parts[1]
      val = parts[2]
      update.call(1, 0, n - 1, i - 1, val)
    else
      # Query: range [l, r] (1-indexed) -> convert to 0-indexed
      l = parts[1]
      r = parts[2]
      output << query.call(1, 0, n - 1, l - 1, r - 1).to_s
    end
  end

  puts output.join("\n")
end

main
