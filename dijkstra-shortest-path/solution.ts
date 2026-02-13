const INF = Number.MAX_SAFE_INTEGER;

function solve(input: string): void {
    const tokens = input.trim().split(/\s+/);
    let idx = 0;
    const n = parseInt(tokens[idx++]);
    const m = parseInt(tokens[idx++]);

    const adj: [number, number][][] = Array.from({length: n + 1}, () => []);
    for (let i = 0; i < m; i++) {
        const u = parseInt(tokens[idx++]);
        const v = parseInt(tokens[idx++]);
        const w = parseInt(tokens[idx++]);
        adj[u].push([v, w]);
    }

    const dist = new Array(n + 1).fill(INF);
    dist[1] = 0;

    // Min-heap: [distance, node]
    const heap: [number, number][] = [[0, 1]];

    function heapPush(item: [number, number]): void {
        heap.push(item);
        let i = heap.length - 1;
        while (i > 0) {
            const parent = (i - 1) >> 1;
            if (heap[parent][0] <= heap[i][0]) break;
            [heap[parent], heap[i]] = [heap[i], heap[parent]];
            i = parent;
        }
    }

    function heapPop(): [number, number] {
        const top = heap[0];
        const last = heap.pop()!;
        if (heap.length > 0) {
            heap[0] = last;
            let i = 0;
            while (true) {
                let smallest = i;
                const left = 2 * i + 1;
                const right = 2 * i + 2;
                if (left < heap.length && heap[left][0] < heap[smallest][0]) smallest = left;
                if (right < heap.length && heap[right][0] < heap[smallest][0]) smallest = right;
                if (smallest === i) break;
                [heap[i], heap[smallest]] = [heap[smallest], heap[i]];
                i = smallest;
            }
        }
        return top;
    }

    while (heap.length > 0) {
        const [d, u] = heapPop();
        if (d > dist[u]) continue;
        for (const [v, w] of adj[u]) {
            const newDist = dist[u] + w;
            if (newDist < dist[v]) {
                dist[v] = newDist;
                heapPush([newDist, v]);
            }
        }
    }

    console.log(dist[n] < INF ? dist[n] : -1);
}

process.stdin.resume();
process.stdin.setEncoding('utf8');
let inputData = '';
process.stdin.on('data', (chunk: string) => { inputData += chunk; });
process.stdin.on('end', () => { solve(inputData); });
