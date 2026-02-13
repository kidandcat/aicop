/*
 * KMP (Knuth-Morris-Pratt) string matching algorithm.
 * Finds all occurrences of pattern P in text T, including overlapping matches.
 *
 * Time: O(N + M), Space: O(N + M) where N = |T|, M = |P|
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Read a line from stdin, stripping the trailing newline. Returns malloc'd buffer. */
static char *read_line(int *out_len) {
    char *line = NULL;
    size_t cap = 0;
    ssize_t len = getline(&line, &cap, stdin);
    if (len < 0) {
        free(line);
        *out_len = 0;
        return NULL;
    }
    /* Strip trailing newline/carriage return */
    while (len > 0 && (line[len - 1] == '\n' || line[len - 1] == '\r')) {
        line[--len] = '\0';
    }
    *out_len = (int)len;
    return line;
}

/* Build the LPS (Longest Proper Prefix which is also Suffix) array */
static int *build_lps(const char *pattern, int m) {
    int *lps = (int *)malloc((size_t)m * sizeof(int));
    lps[0] = 0;
    int len = 0;
    int i = 1;

    while (i < m) {
        if (pattern[i] == pattern[len]) {
            len++;
            lps[i] = len;
            i++;
        } else {
            if (len != 0) {
                len = lps[len - 1];
            } else {
                lps[i] = 0;
                i++;
            }
        }
    }
    return lps;
}

int main(void) {
    int text_len, pat_len;
    char *text = read_line(&text_len);
    char *pattern = read_line(&pat_len);

    if (!text || !pattern || pat_len == 0 || text_len == 0 || pat_len > text_len) {
        printf("0\n\n");
        free(text);
        free(pattern);
        return 0;
    }

    int *lps = build_lps(pattern, pat_len);

    /* Dynamic array for match positions */
    int match_count = 0;
    int match_cap = 16;
    int *matches = (int *)malloc((size_t)match_cap * sizeof(int));

    int i = 0; /* index in text */
    int j = 0; /* index in pattern */

    while (i < text_len) {
        if (text[i] == pattern[j]) {
            i++;
            j++;
        }
        if (j == pat_len) {
            /* Found a match at position i - j */
            if (match_count == match_cap) {
                match_cap *= 2;
                matches = (int *)realloc(matches, (size_t)match_cap * sizeof(int));
            }
            matches[match_count++] = i - j;
            j = lps[j - 1]; /* Continue for overlapping matches */
        } else if (i < text_len && text[i] != pattern[j]) {
            if (j != 0) {
                j = lps[j - 1];
            } else {
                i++;
            }
        }
    }

    printf("%d\n", match_count);
    for (int k = 0; k < match_count; k++) {
        if (k > 0) putchar(' ');
        printf("%d", matches[k]);
    }
    putchar('\n');

    free(lps);
    free(matches);
    free(text);
    free(pattern);

    return 0;
}
