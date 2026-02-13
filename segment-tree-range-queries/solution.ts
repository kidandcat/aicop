function solve(input: string): void {
    const tokens = input.trim().split(/\s+/);
    let idx = 0;
    const n = parseInt(tokens[idx++]);
    const q = parseInt(tokens[idx++]);

    const a = new Array(n);
    for (let i = 0; i < n; i++) {
        a[i] = parseInt(tokens[idx++]);
    }

    const tree = new Array(4 * n).fill(0);

    function build(v: number, tl: number, tr: number): void {
        if (tl === tr) {
            tree[v] = a[tl];
            return;
        }
        const tm = (tl + tr) >> 1;
        build(2 * v, tl, tm);
        build(2 * v + 1, tm + 1, tr);
        tree[v] = tree[2 * v] + tree[2 * v + 1];
    }

    function update(v: number, tl: number, tr: number, pos: number, val: number): void {
        if (tl === tr) {
            tree[v] = val;
            return;
        }
        const tm = (tl + tr) >> 1;
        if (pos <= tm) {
            update(2 * v, tl, tm, pos, val);
        } else {
            update(2 * v + 1, tm + 1, tr, pos, val);
        }
        tree[v] = tree[2 * v] + tree[2 * v + 1];
    }

    function query(v: number, tl: number, tr: number, l: number, r: number): number {
        if (l > r) return 0;
        if (l === tl && r === tr) return tree[v];
        const tm = (tl + tr) >> 1;
        const leftSum = query(2 * v, tl, tm, l, Math.min(r, tm));
        const rightSum = query(2 * v + 1, tm + 1, tr, Math.max(l, tm + 1), r);
        return leftSum + rightSum;
    }

    build(1, 0, n - 1);

    const output: string[] = [];
    for (let i = 0; i < q; i++) {
        const type = parseInt(tokens[idx++]);
        if (type === 1) {
            const pos = parseInt(tokens[idx++]);
            const val = parseInt(tokens[idx++]);
            update(1, 0, n - 1, pos - 1, val);
        } else {
            const l = parseInt(tokens[idx++]);
            const r = parseInt(tokens[idx++]);
            output.push(query(1, 0, n - 1, l - 1, r - 1).toString());
        }
    }
    console.log(output.join('\n'));
}

process.stdin.resume();
process.stdin.setEncoding('utf8');
let inputData = '';
process.stdin.on('data', (chunk: string) => { inputData += chunk; });
process.stdin.on('end', () => { solve(inputData); });
