"""
Longest Increasing Subsequence - O(N log N) solution using patience sorting.

Algorithm:
  Maintain a 'tails' array where tails[i] is the smallest tail element of all
  increasing subsequences of length i+1. For each element, use binary search
  (bisect_left) to find where it belongs in tails:
    - If it's larger than all elements in tails, append it (extends LIS).
    - Otherwise, replace the first element >= it (keeps tails as small as possible).
  The answer is len(tails).
"""

import sys
from bisect import bisect_left


def lis_length(nums):
    tails = []
    for x in nums:
        pos = bisect_left(tails, x)
        if pos == len(tails):
            tails.append(x)
        else:
            tails[pos] = x
    return len(tails)


def main():
    input_data = sys.stdin.buffer.read().decode()
    tokens = input_data.split()
    n = int(tokens[0])
    nums = [int(tokens[i + 1]) for i in range(n)]
    print(lis_length(nums))


if __name__ == "__main__":
    main()
