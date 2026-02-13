use std::io::{self, BufRead, Write, BufWriter};

fn compute_lps(pattern: &[u8]) -> Vec<usize> {
    let m = pattern.len();
    let mut lps = vec![0usize; m];
    let mut length = 0;
    let mut i = 1;

    while i < m {
        if pattern[i] == pattern[length] {
            length += 1;
            lps[i] = length;
            i += 1;
        } else if length != 0 {
            length = lps[length - 1];
        } else {
            lps[i] = 0;
            i += 1;
        }
    }
    lps
}

fn kmp_search(text: &[u8], pattern: &[u8]) -> Vec<usize> {
    let n = text.len();
    let m = pattern.len();
    let lps = compute_lps(pattern);
    let mut results = Vec::new();

    let mut i = 0;
    let mut j = 0;

    while i < n {
        if text[i] == pattern[j] {
            i += 1;
            j += 1;
        }
        if j == m {
            results.push(i - j);
            j = lps[j - 1];
        } else if i < n && text[i] != pattern[j] {
            if j != 0 {
                j = lps[j - 1];
            } else {
                i += 1;
            }
        }
    }
    results
}

fn main() {
    let stdin = io::stdin();
    let stdout = io::stdout();
    let mut out = BufWriter::new(stdout.lock());

    let mut lines = stdin.lock().lines();
    let text = lines.next().unwrap().unwrap();
    let pattern = lines.next().unwrap().unwrap();
    let text = text.trim().as_bytes();
    let pattern = pattern.trim().as_bytes();

    let matches = kmp_search(text, pattern);

    writeln!(out, "{}", matches.len()).unwrap();
    let positions: Vec<String> = matches.iter().map(|x| x.to_string()).collect();
    writeln!(out, "{}", positions.join(" ")).unwrap();
}
