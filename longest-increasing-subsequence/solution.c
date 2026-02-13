/*
 * Longest Increasing Subsequence (strictly increasing) using patience sorting
 * with binary search.
 *
 * Maintains a "tails" array where tails[i] is the smallest tail element for
 * an increasing subsequence of length i+1.
 *
 * Time: O(N log N), Space: O(N)
 */

#include <stdio.h>
#include <stdlib.h>

/*
 * Binary search for the leftmost position in tails[0..len-1] where
 * tails[pos] >= val (lower_bound equivalent for strictly increasing LIS).
 */
static int lower_bound(const int *tails, int len, int val) {
    int lo = 0, hi = len;
    while (lo < hi) {
        int mid = lo + (hi - lo) / 2;
        if (tails[mid] < val) {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    return lo;
}

int main(void) {
    int n;
    scanf("%d", &n);

    if (n <= 0) {
        printf("0\n");
        return 0;
    }

    int *arr = (int *)malloc((size_t)n * sizeof(int));
    for (int i = 0; i < n; i++) {
        scanf("%d", &arr[i]);
    }

    int *tails = (int *)malloc((size_t)n * sizeof(int));
    int lis_len = 0;

    for (int i = 0; i < n; i++) {
        int pos = lower_bound(tails, lis_len, arr[i]);
        tails[pos] = arr[i];
        if (pos == lis_len) {
            lis_len++;
        }
    }

    printf("%d\n", lis_len);

    free(arr);
    free(tails);

    return 0;
}
