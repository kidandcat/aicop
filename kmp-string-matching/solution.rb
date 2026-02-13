# KMP String Matching — O(N + M)
#
# Finds all occurrences of pattern P in text T using the Knuth-Morris-Pratt algorithm.
# Two phases:
#   1. Build the LPS (longest proper prefix which is also suffix) array for P.
#   2. Scan T using the LPS array to skip redundant comparisons.
# Handles overlapping matches.

# Build the failure function (LPS array) for the pattern.
#
# lps[i] = length of the longest proper prefix of pattern[0..i]
# that is also a suffix. This allows us to skip already-matched
# characters when a mismatch occurs during the search phase.
def compute_lps(pattern)
  m = pattern.length
  lps = Array.new(m, 0)
  length = 0 # length of the previous longest prefix suffix
  i = 1

  while i < m
    if pattern[i] == pattern[length]
      length += 1
      lps[i] = length
      i += 1
    else
      if length != 0
        # Fall back to the previous longest prefix suffix.
        # Do NOT increment i — we need to re-check this position.
        length = lps[length - 1]
      else
        lps[i] = 0
        i += 1
      end
    end
  end

  lps
end

# Search for all occurrences of pattern in text using KMP.
#
# Returns a list of 0-indexed starting positions where pattern occurs.
# The search never moves the text pointer backward, ensuring O(N) time.
def kmp_search(text, pattern)
  n = text.length
  m = pattern.length
  lps = compute_lps(pattern)
  results = []

  i = 0 # index in text
  j = 0 # index in pattern

  while i < n
    if text[i] == pattern[j]
      i += 1
      j += 1
    end

    if j == m
      # Full match found at position i - m
      results << (i - j)
      # Use the failure function to continue searching for overlapping matches
      j = lps[j - 1]
    elsif i < n && text[i] != pattern[j]
      if j != 0
        # Mismatch after partial match — use LPS to skip ahead in pattern
        j = lps[j - 1]
      else
        # Mismatch at the start of pattern — advance text pointer
        i += 1
      end
    end
  end

  results
end

def solve
  text = gets.chomp
  pattern = gets.chomp

  matches = kmp_search(text, pattern)

  puts matches.length
  if matches.any?
    puts matches.join(" ")
  else
    puts
  end
end

solve
