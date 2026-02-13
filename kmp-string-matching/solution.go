// KMP String Matching — O(N + M)
//
// Finds all occurrences of pattern P in text T using the Knuth-Morris-Pratt algorithm.
// Two phases:
//  1. Build the LPS (longest proper prefix which is also suffix) array for P.
//  2. Scan T using the LPS array to skip redundant comparisons.
// Handles overlapping matches.
//
// Uses bufio.Scanner with a large buffer to handle strings up to 1,000,000 characters.

package main

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"
)

// computeLPS builds the failure function (LPS array) for the pattern.
//
// lps[i] = length of the longest proper prefix of pattern[0..i]
// that is also a suffix. This allows us to skip already-matched
// characters when a mismatch occurs during the search phase.
func computeLPS(pattern string) []int {
	m := len(pattern)
	lps := make([]int, m)
	length := 0 // length of the previous longest prefix suffix
	i := 1

	for i < m {
		if pattern[i] == pattern[length] {
			length++
			lps[i] = length
			i++
		} else {
			if length != 0 {
				// Fall back to the previous longest prefix suffix.
				// Do NOT increment i — we need to re-check this position.
				length = lps[length-1]
			} else {
				lps[i] = 0
				i++
			}
		}
	}

	return lps
}

// kmpSearch finds all occurrences of pattern in text using KMP.
//
// Returns a slice of 0-indexed starting positions where pattern occurs.
// The search never moves the text pointer backward, ensuring O(N) time.
func kmpSearch(text, pattern string) []int {
	n := len(text)
	m := len(pattern)
	lps := computeLPS(pattern)
	var results []int

	i := 0 // index in text
	j := 0 // index in pattern

	for i < n {
		if text[i] == pattern[j] {
			i++
			j++
		}

		if j == m {
			// Full match found at position i - m
			results = append(results, i-j)
			// Use the failure function to continue searching for overlapping matches
			j = lps[j-1]
		} else if i < n && text[i] != pattern[j] {
			if j != 0 {
				// Mismatch after partial match — use LPS to skip ahead in pattern
				j = lps[j-1]
			} else {
				// Mismatch at the start of pattern — advance text pointer
				i++
			}
		}
	}

	return results
}

func main() {
	// Set a large buffer to handle strings up to 1,000,000 characters
	scanner := bufio.NewScanner(os.Stdin)
	scanner.Buffer(make([]byte, 1024*1024+256), 1024*1024+256)

	scanner.Scan()
	text := scanner.Text()
	scanner.Scan()
	pattern := scanner.Text()

	matches := kmpSearch(text, pattern)

	writer := bufio.NewWriter(os.Stdout)
	defer writer.Flush()

	fmt.Fprintln(writer, len(matches))
	if len(matches) > 0 {
		parts := make([]string, len(matches))
		for i, pos := range matches {
			parts[i] = strconv.Itoa(pos)
		}
		fmt.Fprintln(writer, strings.Join(parts, " "))
	} else {
		fmt.Fprintln(writer)
	}
}
