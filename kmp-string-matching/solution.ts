function computeLps(pattern: string): number[] {
    const m = pattern.length;
    const lps = new Array(m).fill(0);
    let length = 0;
    let i = 1;

    while (i < m) {
        if (pattern[i] === pattern[length]) {
            length++;
            lps[i] = length;
            i++;
        } else {
            if (length !== 0) {
                length = lps[length - 1];
            } else {
                lps[i] = 0;
                i++;
            }
        }
    }
    return lps;
}

function kmpSearch(text: string, pattern: string): number[] {
    const n = text.length;
    const m = pattern.length;
    const lps = computeLps(pattern);
    const results: number[] = [];

    let i = 0;
    let j = 0;

    while (i < n) {
        if (text[i] === pattern[j]) {
            i++;
            j++;
        }
        if (j === m) {
            results.push(i - j);
            j = lps[j - 1];
        } else if (i < n && text[i] !== pattern[j]) {
            if (j !== 0) {
                j = lps[j - 1];
            } else {
                i++;
            }
        }
    }
    return results;
}

function solve(input: string): void {
    const lines = input.split('\n');
    const text = lines[0].trim();
    const pattern = lines[1].trim();

    const matches = kmpSearch(text, pattern);
    console.log(matches.length);
    console.log(matches.join(' '));
}

process.stdin.resume();
process.stdin.setEncoding('utf8');
let inputData = '';
process.stdin.on('data', (chunk: string) => { inputData += chunk; });
process.stdin.on('end', () => { solve(inputData); });
