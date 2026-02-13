// Longest Increasing Subsequence - O(N log N) solution using patience sorting.
//
// Algorithm:
//   Maintain a 'tails' slice where tails[i] is the smallest tail element of all
//   increasing subsequences of length i+1. For each element, use binary search
//   (sort.SearchInts) to find where it belongs in tails:
//     - If it's larger than all elements in tails, append it (extends LIS).
//     - Otherwise, replace the first element >= it (keeps tails as small as possible).
//   The answer is len(tails).

package main

import (
	"bufio"
	"fmt"
	"os"
	"sort"
)

func lisLength(nums []int) int {
	tails := make([]int, 0)

	for _, x := range nums {
		// sort.SearchInts returns the index where x would be inserted in the
		// sorted slice tails. This is equivalent to the leftmost position
		// where tails[pos] >= x.
		pos := sort.SearchInts(tails, x)

		if pos == len(tails) {
			// x is larger than all elements in tails; extend the LIS.
			tails = append(tails, x)
		} else {
			// Replace tails[pos] with x to keep the tail as small as possible.
			tails[pos] = x
		}
	}

	return len(tails)
}

func main() {
	reader := bufio.NewReader(os.Stdin)

	var n int
	fmt.Fscan(reader, &n)

	nums := make([]int, n)
	for i := 0; i < n; i++ {
		fmt.Fscan(reader, &nums[i])
	}

	fmt.Println(lisLength(nums))
}
