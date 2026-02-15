// Longest Increasing Subsequence - O(N log N) solution using patience sorting.
//
// Algorithm:
//   Maintain a 'tails' list where tails[i] is the smallest tail element of all
//   increasing subsequences of length i+1. For each element, use binary search
//   (lowerBound) to find where it belongs in tails:
//     - If it's larger than all elements in tails, append it (extends LIS).
//     - Otherwise, replace the first element >= it (keeps tails as small as possible).
//   The answer is tails.length.

import 'dart:io';

/// Returns the leftmost index where [target] could be inserted in the sorted
/// list [arr] to keep it sorted (i.e., the first position where arr[pos] >= target).
int lowerBound(List<int> arr, int target) {
  var lo = 0;
  var hi = arr.length;
  while (lo < hi) {
    final mid = lo + (hi - lo) ~/ 2;
    if (arr[mid] < target) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}

int lisLength(List<int> nums) {
  final tails = <int>[];
  for (final x in nums) {
    final pos = lowerBound(tails, x);
    if (pos == tails.length) {
      tails.add(x);
    } else {
      tails[pos] = x;
    }
  }
  return tails.length;
}

void main() {
  final lines = <String>[];
  String? line;
  while ((line = stdin.readLineSync()) != null) {
    lines.add(line!);
  }
  final tokens = lines.join(' ').trim().split(RegExp(r'\s+'))
      .where((s) => s.isNotEmpty).toList();

  final n = int.parse(tokens[0]);
  final nums = List<int>.generate(n, (i) => int.parse(tokens[i + 1]));

  print(lisLength(nums));
}
