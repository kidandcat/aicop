#include <iostream>
#include <vector>

using namespace std;

class SegTree {
    vector<long long> tree;
    int n;

    void build(const vector<int>& a, int v, int tl, int tr) {
        if (tl == tr) {
            tree[v] = a[tl];
            return;
        }
        int tm = (tl + tr) / 2;
        build(a, 2 * v, tl, tm);
        build(a, 2 * v + 1, tm + 1, tr);
        tree[v] = tree[2 * v] + tree[2 * v + 1];
    }

    void update(int v, int tl, int tr, int pos, long long val) {
        if (tl == tr) {
            tree[v] = val;
            return;
        }
        int tm = (tl + tr) / 2;
        if (pos <= tm) {
            update(2 * v, tl, tm, pos, val);
        } else {
            update(2 * v + 1, tm + 1, tr, pos, val);
        }
        tree[v] = tree[2 * v] + tree[2 * v + 1];
    }

    long long query(int v, int tl, int tr, int l, int r) const {
        if (l > r) return 0;
        if (l == tl && r == tr) return tree[v];
        int tm = (tl + tr) / 2;
        return query(2 * v, tl, tm, l, min(r, tm))
             + query(2 * v + 1, tm + 1, tr, max(l, tm + 1), r);
    }

public:
    SegTree(const vector<int>& a) : n(a.size()), tree(4 * a.size()) {
        if (n > 0) build(a, 1, 0, n - 1);
    }

    void update(int pos, long long val) {
        update(1, 0, n - 1, pos, val);
    }

    long long query(int l, int r) const {
        return query(1, 0, n - 1, l, r);
    }
};

int main() {
    ios_base::sync_with_stdio(false);
    cin.tie(nullptr);

    int n, q;
    cin >> n >> q;

    vector<int> a(n);
    for (int i = 0; i < n; i++) {
        cin >> a[i];
    }

    SegTree st(a);

    for (int i = 0; i < q; i++) {
        int type;
        cin >> type;
        if (type == 1) {
            int pos;
            long long val;
            cin >> pos >> val;
            st.update(pos - 1, val);
        } else {
            int l, r;
            cin >> l >> r;
            cout << st.query(l - 1, r - 1) << "\n";
        }
    }

    return 0;
}
