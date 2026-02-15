// Dijkstra's Shortest Path — O((N+M) log N)
//
// Finds the shortest path from node 1 to node N in a weighted directed graph.
// Uses a custom MinHeap (binary heap) with lazy deletion.

import 'dart:io';

const int inf = 1 << 62;

class Edge {
  final int v;
  final int w;
  Edge(this.v, this.w);
}

class Item {
  final int dist;
  final int node;
  Item(this.dist, this.node);
}

/// A binary min-heap ordered by [Item.dist].
class MinHeap {
  final List<Item> _data = [];

  int get length => _data.length;
  bool get isNotEmpty => _data.isNotEmpty;

  void push(Item item) {
    _data.add(item);
    _siftUp(_data.length - 1);
  }

  Item pop() {
    final top = _data.first;
    final last = _data.removeLast();
    if (_data.isNotEmpty) {
      _data[0] = last;
      _siftDown(0);
    }
    return top;
  }

  void _siftUp(int i) {
    while (i > 0) {
      final parent = (i - 1) >> 1;
      if (_data[i].dist >= _data[parent].dist) break;
      _swap(i, parent);
      i = parent;
    }
  }

  void _siftDown(int i) {
    final n = _data.length;
    while (true) {
      var smallest = i;
      final left = 2 * i + 1;
      final right = 2 * i + 2;
      if (left < n && _data[left].dist < _data[smallest].dist) {
        smallest = left;
      }
      if (right < n && _data[right].dist < _data[smallest].dist) {
        smallest = right;
      }
      if (smallest == i) break;
      _swap(i, smallest);
      i = smallest;
    }
  }

  void _swap(int i, int j) {
    final tmp = _data[i];
    _data[i] = _data[j];
    _data[j] = tmp;
  }
}

void main() {
  final lines = <String>[];
  String? line;
  while ((line = stdin.readLineSync()) != null) {
    lines.add(line!);
  }
  final tokens = lines.join(' ').trim().split(RegExp(r'\s+'))
      .where((s) => s.isNotEmpty).toList();
  var idx = 0;
  int next() => int.parse(tokens[idx++]);

  final n = next();
  final m = next();

  // Build adjacency list (1-indexed).
  final adj = List<List<Edge>>.generate(n + 1, (_) => []);
  for (var i = 0; i < m; i++) {
    final u = next();
    final v = next();
    final w = next();
    adj[u].add(Edge(v, w));
  }

  // Initialize distances.
  final dist = List<int>.filled(n + 1, inf);
  dist[1] = 0;

  // Dijkstra with min-heap and lazy deletion.
  final pq = MinHeap()..push(Item(0, 1));
  while (pq.isNotEmpty) {
    final cur = pq.pop();
    final u = cur.node;
    final d = cur.dist;
    if (d > dist[u]) continue;
    for (final e in adj[u]) {
      final newDist = dist[u] + e.w;
      if (newDist < dist[e.v]) {
        dist[e.v] = newDist;
        pq.push(Item(newDist, e.v));
      }
    }
  }

  print(dist[n] < inf ? dist[n] : -1);
}
