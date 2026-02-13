// KMP String Matching — O(N + M)
//
// Finds all occurrences of pattern P in text T using the Knuth-Morris-Pratt algorithm.
// Two phases:
//   1. Build the LPS (longest proper prefix which is also suffix) array for P.
//   2. Scan T using the LPS array to skip redundant comparisons.
// Handles overlapping matches.
//
// Compatible with Zig 0.15+: uses std.fs.File.stdin()/stdout() for I/O
// and reads all input at once for simplicity.

const std = @import("std");

/// Build the failure function (LPS array) for the pattern.
///
/// lps[i] = length of the longest proper prefix of pattern[0..i]
/// that is also a suffix. This allows us to skip already-matched
/// characters when a mismatch occurs during the search phase.
fn computeLPS(pattern: []const u8, lps: []usize) void {
    lps[0] = 0;
    var length: usize = 0; // length of the previous longest prefix suffix
    var i: usize = 1;

    while (i < pattern.len) {
        if (pattern[i] == pattern[length]) {
            length += 1;
            lps[i] = length;
            i += 1;
        } else {
            if (length != 0) {
                // Fall back to the previous longest prefix suffix.
                // Do NOT increment i — we need to re-check this position.
                length = lps[length - 1];
            } else {
                lps[i] = 0;
                i += 1;
            }
        }
    }
}

/// Search for all occurrences of pattern in text using KMP.
///
/// Writes 0-indexed starting positions into the results buffer.
/// Returns the number of matches found.
/// The search never moves the text pointer backward, ensuring O(N) time.
fn kmpSearch(text: []const u8, pattern: []const u8, lps: []const usize, results: []usize) usize {
    const n = text.len;
    const m = pattern.len;
    var count: usize = 0;

    var i: usize = 0; // index in text
    var j: usize = 0; // index in pattern

    while (i < n) {
        if (text[i] == pattern[j]) {
            i += 1;
            j += 1;
        }

        if (j == m) {
            // Full match found at position i - m
            results[count] = i - j;
            count += 1;
            // Use the failure function to continue searching for overlapping matches
            j = lps[j - 1];
        } else if (i < n and text[i] != pattern[j]) {
            if (j != 0) {
                // Mismatch after partial match — use LPS to skip ahead in pattern
                j = lps[j - 1];
            } else {
                // Mismatch at the start of pattern — advance text pointer
                i += 1;
            }
        }
    }

    return count;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Read all of stdin into memory
    const stdin = std.fs.File.stdin();
    const content = try stdin.readToEndAlloc(allocator, 1024 * 1024 * 4);
    defer allocator.free(content);

    // Split input into lines
    var line_it = std.mem.splitScalar(u8, content, '\n');
    const text_raw = line_it.next() orelse return;
    const pattern_raw = line_it.next() orelse return;

    // Strip trailing \r if present (Windows line endings)
    const text = if (text_raw.len > 0 and text_raw[text_raw.len - 1] == '\r')
        text_raw[0 .. text_raw.len - 1]
    else
        text_raw;
    const pattern = if (pattern_raw.len > 0 and pattern_raw[pattern_raw.len - 1] == '\r')
        pattern_raw[0 .. pattern_raw.len - 1]
    else
        pattern_raw;

    const m = pattern.len;
    const n = text.len;

    // Allocate LPS array
    const lps = try allocator.alloc(usize, m);
    defer allocator.free(lps);

    // Build the failure function
    computeLPS(pattern, lps);

    // Allocate results array (worst case: n - m + 1 matches)
    const max_matches = if (n >= m) n - m + 1 else 0;
    const results = try allocator.alloc(usize, max_matches + 1);
    defer allocator.free(results);

    // Run KMP search
    const count = kmpSearch(text, pattern, lps, results);

    // Output results
    const stdout = std.fs.File.stdout();
    var buf: [32]u8 = undefined;

    // Print count
    var msg = try std.fmt.bufPrint(&buf, "{d}\n", .{count});
    _ = try stdout.write(msg);

    // Print positions
    if (count > 0) {
        for (0..count) |idx| {
            if (idx > 0) {
                _ = try stdout.write(" ");
            }
            msg = try std.fmt.bufPrint(&buf, "{d}", .{results[idx]});
            _ = try stdout.write(msg);
        }
        _ = try stdout.write("\n");
    } else {
        _ = try stdout.write("\n");
    }
}
