function lowerBound(arr: number[], target: number): number {
    let lo = 0;
    let hi = arr.length;
    while (lo < hi) {
        const mid = (lo + hi) >> 1;
        if (arr[mid] < target) {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    return lo;
}

function lisLength(nums: number[]): number {
    const tails: number[] = [];
    for (const x of nums) {
        const pos = lowerBound(tails, x);
        if (pos === tails.length) {
            tails.push(x);
        } else {
            tails[pos] = x;
        }
    }
    return tails.length;
}

function solve(input: string): void {
    const tokens = input.trim().split(/\s+/);
    const n = parseInt(tokens[0]);
    const nums = new Array(n);
    for (let i = 0; i < n; i++) {
        nums[i] = parseInt(tokens[i + 1]);
    }
    console.log(lisLength(nums));
}

process.stdin.resume();
process.stdin.setEncoding('utf8');
let inputData = '';
process.stdin.on('data', (chunk: string) => { inputData += chunk; });
process.stdin.on('end', () => { solve(inputData); });
