/*
 * Segment tree with point updates and range sum queries.
 * Array-based implementation using 1-indexed tree of size 4*N.
 *
 * Operations:
 *   1 i v  -> set arr[i] = v (1-indexed)
 *   2 l r  -> query sum of arr[l..r] (1-indexed, inclusive)
 *
 * Time: O(log N) per operation, Space: O(N)
 */

#include <stdio.h>
#include <stdlib.h>

typedef long long ll;

static ll *tree;
static int tree_n;

static void build(const int *arr, int node, int start, int end) {
    if (start == end) {
        tree[node] = arr[start];
    } else {
        int mid = (start + end) / 2;
        build(arr, 2 * node, start, mid);
        build(arr, 2 * node + 1, mid + 1, end);
        tree[node] = tree[2 * node] + tree[2 * node + 1];
    }
}

static void update(int node, int start, int end, int idx, int val) {
    if (start == end) {
        tree[node] = val;
    } else {
        int mid = (start + end) / 2;
        if (idx <= mid) {
            update(2 * node, start, mid, idx, val);
        } else {
            update(2 * node + 1, mid + 1, end, idx, val);
        }
        tree[node] = tree[2 * node] + tree[2 * node + 1];
    }
}

static ll query(int node, int start, int end, int l, int r) {
    if (r < start || end < l) {
        return 0;
    }
    if (l <= start && end <= r) {
        return tree[node];
    }
    int mid = (start + end) / 2;
    ll left_sum = query(2 * node, start, mid, l, r);
    ll right_sum = query(2 * node + 1, mid + 1, end, l, r);
    return left_sum + right_sum;
}

int main(void) {
    int n, q;
    scanf("%d %d", &n, &q);

    tree_n = n;

    int *arr = (int *)malloc((size_t)(n + 1) * sizeof(int));
    for (int i = 1; i <= n; i++) {
        scanf("%d", &arr[i]);
    }

    /* Allocate segment tree: 4*N nodes, 1-indexed */
    tree = (ll *)calloc((size_t)(4 * n + 4), sizeof(ll));

    build(arr, 1, 1, n);

    /* Use a write buffer for faster output */
    char *out_buf = (char *)malloc(20 * (size_t)q);
    int out_pos = 0;

    for (int i = 0; i < q; i++) {
        int type;
        scanf("%d", &type);
        if (type == 1) {
            int idx, val;
            scanf("%d %d", &idx, &val);
            update(1, 1, n, idx, val);
        } else {
            int l, r;
            scanf("%d %d", &l, &r);
            ll result = query(1, 1, n, l, r);
            out_pos += sprintf(out_buf + out_pos, "%lld\n", result);
        }
    }

    /* Flush output buffer */
    if (out_pos > 0) {
        fwrite(out_buf, 1, (size_t)out_pos, stdout);
    }

    free(out_buf);
    free(arr);
    free(tree);

    return 0;
}
