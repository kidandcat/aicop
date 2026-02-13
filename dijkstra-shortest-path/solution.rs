use std::cmp::Reverse;
use std::collections::BinaryHeap;
use std::io::{self, Read};

fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let mut iter = input.split_whitespace();

    let n: usize = iter.next().unwrap().parse().unwrap();
    let m: usize = iter.next().unwrap().parse().unwrap();

    let mut adj: Vec<Vec<(usize, i64)>> = vec![vec![]; n + 1];
    for _ in 0..m {
        let u: usize = iter.next().unwrap().parse().unwrap();
        let v: usize = iter.next().unwrap().parse().unwrap();
        let w: i64 = iter.next().unwrap().parse().unwrap();
        adj[u].push((v, w));
    }

    const INF: i64 = i64::MAX;
    let mut dist = vec![INF; n + 1];
    dist[1] = 0;

    let mut heap = BinaryHeap::new();
    heap.push(Reverse((0i64, 1usize)));

    while let Some(Reverse((d, u))) = heap.pop() {
        if d > dist[u] {
            continue;
        }
        for &(v, w) in &adj[u] {
            let new_dist = dist[u] + w;
            if new_dist < dist[v] {
                dist[v] = new_dist;
                heap.push(Reverse((new_dist, v)));
            }
        }
    }

    if dist[n] == INF {
        println!("-1");
    } else {
        println!("{}", dist[n]);
    }
}
