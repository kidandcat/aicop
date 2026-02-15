// KMP String Matching — O(N + M)
//
// Finds all occurrences of pattern P in text T using the Knuth-Morris-Pratt algorithm.
// Two phases:
//  1. Build the LPS (longest proper prefix which is also suffix) array for P.
//  2. Scan T using the LPS array to skip redundant comparisons.
// Handles overlapping matches.

import 'dart:io';

/// Build the failure function (LPS array) for the pattern.
///
/// lps[i] = length of the longest proper prefix of pattern[0..i]
/// that is also a suffix. This allows us to skip already-matched
/// characters when a mismatch occurs during the search phase.
List<int> computeLps(String pattern) {
  final m = pattern.length;
  final lps = List<int>.filled(m, 0);
  var length = 0; // length of the previous longest prefix suffix
  var i = 1;

  while (i < m) {
    if (pattern[i] == pattern[length]) {
      length++;
      lps[i] = length;
      i++;
    } else {
      if (length != 0) {
        // Fall back to the previous longest prefix suffix.
        // Do NOT increment i — we need to re-check this position.
        length = lps[length - 1];
      } else {
        lps[i] = 0;
        i++;
      }
    }
  }

  return lps;
}

/// Search for all occurrences of pattern in text using KMP.
///
/// Returns a list of 0-indexed starting positions where pattern occurs.
/// The search never moves the text pointer backward, ensuring O(N) time.
List<int> kmpSearch(String text, String pattern) {
  final n = text.length;
  final m = pattern.length;
  final lps = computeLps(pattern);
  final results = <int>[];

  var i = 0; // index in text
  var j = 0; // index in pattern

  while (i < n) {
    if (text[i] == pattern[j]) {
      i++;
      j++;
    }

    if (j == m) {
      // Full match found at position i - m
      results.add(i - j);
      // Use the failure function to continue searching for overlapping matches
      j = lps[j - 1];
    } else if (i < n && text[i] != pattern[j]) {
      if (j != 0) {
        // Mismatch after partial match — use LPS to skip ahead in pattern
        j = lps[j - 1];
      } else {
        // Mismatch at the start of pattern — advance text pointer
        i++;
      }
    }
  }

  return results;
}

void main() {
  final text = stdin.readLineSync()!;
  final pattern = stdin.readLineSync()!;

  final matches = kmpSearch(text, pattern);

  print(matches.length);
  if (matches.isNotEmpty) {
    print(matches.join(' '));
  } else {
    print('');
  }
}
