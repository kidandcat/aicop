/*
 * Dijkstra's shortest path from node 1 to node N using a binary min-heap
 * priority queue and adjacency list representation.
 *
 * Time: O((N + M) log N), Space: O(N + M)
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define INF 1000000000000000000LL /* 10^18 */

typedef long long ll;

/* --- Adjacency list with dynamic arrays --- */

typedef struct {
    int to;
    ll weight;
} Edge;

typedef struct {
    Edge *edges;
    int size;
    int cap;
} AdjList;

static void adj_init(AdjList *a) {
    a->edges = NULL;
    a->size = 0;
    a->cap = 0;
}

static void adj_push(AdjList *a, int to, ll w) {
    if (a->size == a->cap) {
        a->cap = a->cap == 0 ? 4 : a->cap * 2;
        a->edges = (Edge *)realloc(a->edges, (size_t)a->cap * sizeof(Edge));
    }
    a->edges[a->size].to = to;
    a->edges[a->size].weight = w;
    a->size++;
}

static void adj_free(AdjList *a) {
    free(a->edges);
}

/* --- Binary min-heap priority queue --- */

typedef struct {
    int node;
    ll dist;
} HeapNode;

typedef struct {
    HeapNode *data;
    int size;
    int cap;
} MinHeap;

static void heap_init(MinHeap *h, int cap) {
    h->data = (HeapNode *)malloc((size_t)cap * sizeof(HeapNode));
    h->size = 0;
    h->cap = cap;
}

static void heap_free(MinHeap *h) {
    free(h->data);
}

static void heap_swap(HeapNode *a, HeapNode *b) {
    HeapNode tmp = *a;
    *a = *b;
    *b = tmp;
}

static void heap_push(MinHeap *h, int node, ll dist) {
    if (h->size == h->cap) {
        h->cap *= 2;
        h->data = (HeapNode *)realloc(h->data, (size_t)h->cap * sizeof(HeapNode));
    }
    int i = h->size++;
    h->data[i].node = node;
    h->data[i].dist = dist;
    /* Sift up */
    while (i > 0) {
        int parent = (i - 1) / 2;
        if (h->data[parent].dist > h->data[i].dist) {
            heap_swap(&h->data[parent], &h->data[i]);
            i = parent;
        } else {
            break;
        }
    }
}

static HeapNode heap_pop(MinHeap *h) {
    HeapNode top = h->data[0];
    h->data[0] = h->data[--h->size];
    /* Sift down */
    int i = 0;
    for (;;) {
        int smallest = i;
        int left = 2 * i + 1;
        int right = 2 * i + 2;
        if (left < h->size && h->data[left].dist < h->data[smallest].dist)
            smallest = left;
        if (right < h->size && h->data[right].dist < h->data[smallest].dist)
            smallest = right;
        if (smallest != i) {
            heap_swap(&h->data[i], &h->data[smallest]);
            i = smallest;
        } else {
            break;
        }
    }
    return top;
}

int main(void) {
    int n, m;
    scanf("%d %d", &n, &m);

    AdjList *adj = (AdjList *)malloc((size_t)(n + 1) * sizeof(AdjList));
    for (int i = 0; i <= n; i++) {
        adj_init(&adj[i]);
    }

    for (int i = 0; i < m; i++) {
        int u, v;
        ll w;
        scanf("%d %d %lld", &u, &v, &w);
        adj_push(&adj[u], v, w);
    }

    ll *dist = (ll *)malloc((size_t)(n + 1) * sizeof(ll));
    for (int i = 0; i <= n; i++) {
        dist[i] = INF;
    }
    dist[1] = 0;

    MinHeap heap;
    heap_init(&heap, n + 1);
    heap_push(&heap, 1, 0);

    while (heap.size > 0) {
        HeapNode cur = heap_pop(&heap);
        int u = cur.node;
        ll d = cur.dist;

        if (d > dist[u]) continue; /* Stale entry */

        if (u == n) break; /* Early exit: reached target */

        for (int i = 0; i < adj[u].size; i++) {
            int v = adj[u].edges[i].to;
            ll nd = d + adj[u].edges[i].weight;
            if (nd < dist[v]) {
                dist[v] = nd;
                heap_push(&heap, v, nd);
            }
        }
    }

    if (dist[n] >= INF) {
        printf("-1\n");
    } else {
        printf("%lld\n", dist[n]);
    }

    /* Cleanup */
    for (int i = 0; i <= n; i++) {
        adj_free(&adj[i]);
    }
    free(adj);
    free(dist);
    heap_free(&heap);

    return 0;
}
