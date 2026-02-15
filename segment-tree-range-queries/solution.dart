// Segment Tree - Range Sum Queries with Point Updates
//
// Approach:
//   - Build a recursive segment tree stored in a 1-indexed list of size 4*N.
//   - Node v covers the segment [tl, tr].
//   - Left child = 2*v, right child = 2*v+1.
//   - Each node stores the sum of its segment as int (64-bit on all modern Dart
//     platforms, sufficient for large sums).
//   - Update: traverse to the leaf and propagate sums back up -> O(log N).
//   - Query: split the range across children recursively -> O(log N).
//
// Uses stdin.readLineSync() with buffered StringBuffer output for fast I/O.

import 'dart:io';
import 'dart:math';

late List<int> tree;

/// Builds the segment tree from array [a].
/// [v] = current node index, [tl]..[tr] = segment covered (0-indexed).
void build(List<int> a, int v, int tl, int tr) {
  if (tl == tr) {
    tree[v] = a[tl];
    return;
  }
  final tm = (tl + tr) ~/ 2;
  build(a, 2 * v, tl, tm);
  build(a, 2 * v + 1, tm + 1, tr);
  tree[v] = tree[2 * v] + tree[2 * v + 1];
}

/// Sets position [pos] to value [val] and propagates sums upward.
void update(int v, int tl, int tr, int pos, int val) {
  if (tl == tr) {
    tree[v] = val;
    return;
  }
  final tm = (tl + tr) ~/ 2;
  if (pos <= tm) {
    update(2 * v, tl, tm, pos, val);
  } else {
    update(2 * v + 1, tm + 1, tr, pos, val);
  }
  tree[v] = tree[2 * v] + tree[2 * v + 1];
}

/// Returns the sum of elements in range [l, r] (0-indexed).
int query(int v, int tl, int tr, int l, int r) {
  if (l > r) return 0;
  if (l == tl && r == tr) return tree[v];
  final tm = (tl + tr) ~/ 2;
  return query(2 * v, tl, tm, l, min(r, tm)) +
      query(2 * v + 1, tm + 1, tr, max(l, tm + 1), r);
}

void main() {
  // Read all stdin for fast tokenized parsing
  final lines = <String>[];
  String? line;
  while ((line = stdin.readLineSync()) != null) {
    lines.add(line!);
  }
  final tokens = lines.join(' ').trim().split(RegExp(r'\s+'))
      .where((s) => s.isNotEmpty).toList();
  var idx = 0;

  // Read N and Q
  final n = int.parse(tokens[idx++]);
  final q = int.parse(tokens[idx++]);

  // Read the initial array
  final a = List<int>.generate(n, (_) => int.parse(tokens[idx++]));

  // Allocate and build the segment tree
  tree = List<int>.filled(4 * n, 0);
  build(a, 1, 0, n - 1);

  // Process queries with buffered output
  final output = StringBuffer();
  for (var i = 0; i < q; i++) {
    final qtype = int.parse(tokens[idx++]);
    if (qtype == 1) {
      // Update: position (1-indexed) -> convert to 0-indexed
      final pos = int.parse(tokens[idx++]);
      final val = int.parse(tokens[idx++]);
      update(1, 0, n - 1, pos - 1, val);
    } else {
      // Query: range [l, r] (1-indexed) -> convert to 0-indexed
      final l = int.parse(tokens[idx++]);
      final r = int.parse(tokens[idx++]);
      output.writeln(query(1, 0, n - 1, l - 1, r - 1));
    }
  }

  stdout.write(output);
}
