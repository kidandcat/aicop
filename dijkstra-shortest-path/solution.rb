# Dijkstra's Shortest Path — O((N+M) log N)
#
# Finds the shortest path from node 1 to node N in a weighted directed graph.
# Implements a custom binary min-heap since Ruby has no built-in priority queue.

INF = 10**18

# Binary min-heap implementation for (distance, node) pairs.
# Ordered by distance (first element of the pair).
class MinHeap
  def initialize
    @data = []
  end

  def push(pair)
    @data.push(pair)
    sift_up(@data.size - 1)
  end

  def pop
    return nil if @data.empty?
    top = @data[0]
    last = @data.pop
    unless @data.empty?
      @data[0] = last
      sift_down(0)
    end
    top
  end

  def empty?
    @data.empty?
  end

  private

  def sift_up(i)
    while i > 0
      parent = (i - 1) / 2
      break if @data[parent][0] <= @data[i][0]
      @data[parent], @data[i] = @data[i], @data[parent]
      i = parent
    end
  end

  def sift_down(i)
    size = @data.size
    loop do
      smallest = i
      left = 2 * i + 1
      right = 2 * i + 2
      smallest = left if left < size && @data[left][0] < @data[smallest][0]
      smallest = right if right < size && @data[right][0] < @data[smallest][0]
      break if smallest == i
      @data[i], @data[smallest] = @data[smallest], @data[i]
      i = smallest
    end
  end
end

def solve
  input = $stdin.read.split.map(&:to_i)
  idx = 0

  n = input[idx]; idx += 1
  m = input[idx]; idx += 1

  # Build adjacency list: adj[u] = array of [v, w]
  adj = Array.new(n + 1) { [] }
  m.times do
    u = input[idx]; idx += 1
    v = input[idx]; idx += 1
    w = input[idx]; idx += 1
    adj[u].push([v, w])
  end

  # Distance array initialized to infinity
  dist = Array.new(n + 1, INF)
  dist[1] = 0

  # Min-heap: [distance, node]
  heap = MinHeap.new
  heap.push([0, 1])

  until heap.empty?
    d, u = heap.pop

    # Lazy deletion: skip if this entry is outdated
    next if d > dist[u]

    # Relax all outgoing edges from u
    adj[u].each do |v, w|
      new_dist = dist[u] + w
      if new_dist < dist[v]
        dist[v] = new_dist
        heap.push([new_dist, v])
      end
    end
  end

  # Output result
  puts dist[n] < INF ? dist[n] : -1
end

solve
