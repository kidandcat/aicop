// Dijkstra's Shortest Path — O((N+M) log N)
//
// Finds the shortest path from node 1 to node N in a weighted directed graph.
// Uses container/heap for the min-heap with lazy deletion.

package main

import (
	"bufio"
	"container/heap"
	"fmt"
	"os"
)

const INF = int64(1e18)

// Edge represents a directed edge to node V with weight W.
type Edge struct {
	V int
	W int64
}

// Item in the priority queue: distance and node.
type Item struct {
	Dist int64
	Node int
}

// PQ implements heap.Interface for a min-heap of Items.
type PQ []Item

func (pq PQ) Len() int            { return len(pq) }
func (pq PQ) Less(i, j int) bool  { return pq[i].Dist < pq[j].Dist }
func (pq PQ) Swap(i, j int)       { pq[i], pq[j] = pq[j], pq[i] }
func (pq *PQ) Push(x interface{}) { *pq = append(*pq, x.(Item)) }
func (pq *PQ) Pop() interface{} {
	old := *pq
	n := len(old)
	item := old[n-1]
	*pq = old[:n-1]
	return item
}

func main() {
	reader := bufio.NewReader(os.Stdin)

	var n, m int
	fmt.Fscan(reader, &n, &m)

	// Build adjacency list: adj[u] = slice of Edge{v, w}
	adj := make([][]Edge, n+1)
	for i := 0; i < m; i++ {
		var u, v int
		var w int64
		fmt.Fscan(reader, &u, &v, &w)
		adj[u] = append(adj[u], Edge{v, w})
	}

	// Distance array initialized to infinity
	dist := make([]int64, n+1)
	for i := range dist {
		dist[i] = INF
	}
	dist[1] = 0

	// Min-heap: (distance, node)
	pq := &PQ{{Dist: 0, Node: 1}}
	heap.Init(pq)

	for pq.Len() > 0 {
		cur := heap.Pop(pq).(Item)
		u := cur.Node
		d := cur.Dist

		// Lazy deletion: skip if this entry is outdated
		if d > dist[u] {
			continue
		}

		// Relax all outgoing edges from u
		for _, e := range adj[u] {
			newDist := dist[u] + e.W
			if newDist < dist[e.V] {
				dist[e.V] = newDist
				heap.Push(pq, Item{Dist: newDist, Node: e.V})
			}
		}
	}

	// Output result
	if dist[n] < INF {
		fmt.Println(dist[n])
	} else {
		fmt.Println(-1)
	}
}
