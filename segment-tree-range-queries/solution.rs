use std::io::{self, Read, Write, BufWriter};

struct SegTree {
    tree: Vec<i64>,
}

impl SegTree {
    fn new(a: &[i64]) -> Self {
        let n = a.len();
        let mut st = SegTree {
            tree: vec![0; 4 * n],
        };
        if n > 0 {
            st.build(a, 1, 0, n - 1);
        }
        st
    }

    fn build(&mut self, a: &[i64], v: usize, tl: usize, tr: usize) {
        if tl == tr {
            self.tree[v] = a[tl];
            return;
        }
        let tm = (tl + tr) / 2;
        self.build(a, 2 * v, tl, tm);
        self.build(a, 2 * v + 1, tm + 1, tr);
        self.tree[v] = self.tree[2 * v] + self.tree[2 * v + 1];
    }

    fn update(&mut self, v: usize, tl: usize, tr: usize, pos: usize, val: i64) {
        if tl == tr {
            self.tree[v] = val;
            return;
        }
        let tm = (tl + tr) / 2;
        if pos <= tm {
            self.update(2 * v, tl, tm, pos, val);
        } else {
            self.update(2 * v + 1, tm + 1, tr, pos, val);
        }
        self.tree[v] = self.tree[2 * v] + self.tree[2 * v + 1];
    }

    fn query(&self, v: usize, tl: usize, tr: usize, l: usize, r: usize) -> i64 {
        if l > r || l > tr || r < tl {
            return 0;
        }
        if l <= tl && tr <= r {
            return self.tree[v];
        }
        let tm = (tl + tr) / 2;
        self.query(2 * v, tl, tm, l, r.min(tm))
            + self.query(2 * v + 1, tm + 1, tr, l.max(tm + 1), r)
    }
}

fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let stdout = io::stdout();
    let mut out = BufWriter::new(stdout.lock());

    let mut iter = input.split_whitespace();
    let n: usize = iter.next().unwrap().parse().unwrap();
    let q: usize = iter.next().unwrap().parse().unwrap();

    let a: Vec<i64> = (0..n)
        .map(|_| iter.next().unwrap().parse().unwrap())
        .collect();

    let mut st = SegTree::new(&a);

    for _ in 0..q {
        let t: usize = iter.next().unwrap().parse().unwrap();
        if t == 1 {
            let i: usize = iter.next().unwrap().parse().unwrap();
            let v: i64 = iter.next().unwrap().parse().unwrap();
            st.update(1, 0, n - 1, i - 1, v);
        } else {
            let l: usize = iter.next().unwrap().parse().unwrap();
            let r: usize = iter.next().unwrap().parse().unwrap();
            writeln!(out, "{}", st.query(1, 0, n - 1, l - 1, r - 1)).unwrap();
        }
    }
}
