use std::io::{self, Read};

fn lower_bound(arr: &[i64], target: i64) -> usize {
    let mut lo = 0;
    let mut hi = arr.len();
    while lo < hi {
        let mid = lo + (hi - lo) / 2;
        if arr[mid] < target {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    lo
}

fn lis_length(nums: &[i64]) -> usize {
    let mut tails: Vec<i64> = Vec::new();
    for &x in nums {
        let pos = lower_bound(&tails, x);
        if pos == tails.len() {
            tails.push(x);
        } else {
            tails[pos] = x;
        }
    }
    tails.len()
}

fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let mut iter = input.split_whitespace();

    let n: usize = iter.next().unwrap().parse().unwrap();
    let nums: Vec<i64> = (0..n)
        .map(|_| iter.next().unwrap().parse().unwrap())
        .collect();

    println!("{}", lis_length(&nums));
}
