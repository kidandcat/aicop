// Segment Tree - Range Sum Queries with Point Updates
//
// Approach:
//   - Build a recursive segment tree stored in a 1-indexed slice of size 4*N.
//   - Node v covers the segment [tl, tr].
//   - Left child = 2*v, right child = 2*v+1.
//   - Each node stores the sum of its segment as int64 (to handle large sums).
//   - Update: traverse to the leaf and propagate sums back up -> O(log N).
//   - Query: split the range across children recursively -> O(log N).
//
// Uses bufio.Scanner for fast I/O (critical for large inputs in Go).

package main

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"
)

var tree []int64

// build constructs the segment tree from array a.
// v = current node index, tl..tr = segment covered (0-indexed).
func build(a []int64, v, tl, tr int) {
	if tl == tr {
		tree[v] = a[tl]
		return
	}
	tm := (tl + tr) / 2
	build(a, 2*v, tl, tm)
	build(a, 2*v+1, tm+1, tr)
	tree[v] = tree[2*v] + tree[2*v+1]
}

// update sets position pos to value val and propagates sums upward.
func update(v, tl, tr, pos int, val int64) {
	if tl == tr {
		tree[v] = val
		return
	}
	tm := (tl + tr) / 2
	if pos <= tm {
		update(2*v, tl, tm, pos, val)
	} else {
		update(2*v+1, tm+1, tr, pos, val)
	}
	tree[v] = tree[2*v] + tree[2*v+1]
}

// query returns the sum of elements in range [l, r] (0-indexed).
func query(v, tl, tr, l, r int) int64 {
	if l > r {
		return 0
	}
	if l == tl && r == tr {
		return tree[v]
	}
	tm := (tl + tr) / 2
	leftR := r
	if tm < leftR {
		leftR = tm
	}
	rightL := l
	if tm+1 > rightL {
		rightL = tm + 1
	}
	return query(2*v, tl, tm, l, leftR) + query(2*v+1, tm+1, tr, rightL, r)
}

func main() {
	reader := bufio.NewReaderSize(os.Stdin, 1<<20)
	writer := bufio.NewWriterSize(os.Stdout, 1<<20)
	defer writer.Flush()

	// Read N and Q
	line, _ := reader.ReadString('\n')
	line = strings.TrimSpace(line)
	parts := strings.Fields(line)
	n, _ := strconv.Atoi(parts[0])
	q, _ := strconv.Atoi(parts[1])

	// Read the initial array
	line, _ = reader.ReadString('\n')
	line = strings.TrimSpace(line)
	parts = strings.Fields(line)
	a := make([]int64, n)
	for i := 0; i < n; i++ {
		val, _ := strconv.ParseInt(parts[i], 10, 64)
		a[i] = val
	}

	// Allocate and build the segment tree
	tree = make([]int64, 4*n)
	build(a, 1, 0, n-1)

	// Process queries
	for i := 0; i < q; i++ {
		line, _ = reader.ReadString('\n')
		line = strings.TrimSpace(line)
		parts = strings.Fields(line)
		qtype, _ := strconv.Atoi(parts[0])

		if qtype == 1 {
			// Update: position idx (1-indexed) -> convert to 0-indexed
			idx, _ := strconv.Atoi(parts[1])
			val, _ := strconv.ParseInt(parts[2], 10, 64)
			update(1, 0, n-1, idx-1, val)
		} else {
			// Query: range [l, r] (1-indexed) -> convert to 0-indexed
			l, _ := strconv.Atoi(parts[1])
			r, _ := strconv.Atoi(parts[2])
			result := query(1, 0, n-1, l-1, r-1)
			fmt.Fprintln(writer, result)
		}
	}
}
