#include <iostream>
#include <vector>
#include <string>

using namespace std;

vector<int> compute_lps(const string& pattern) {
    int m = pattern.size();
    vector<int> lps(m, 0);
    int length = 0;
    int i = 1;

    while (i < m) {
        if (pattern[i] == pattern[length]) {
            length++;
            lps[i] = length;
            i++;
        } else if (length != 0) {
            length = lps[length - 1];
        } else {
            lps[i] = 0;
            i++;
        }
    }
    return lps;
}

vector<int> kmp_search(const string& text, const string& pattern) {
    int n = text.size();
    int m = pattern.size();
    vector<int> lps = compute_lps(pattern);
    vector<int> results;

    int i = 0, j = 0;
    while (i < n) {
        if (text[i] == pattern[j]) {
            i++;
            j++;
        }
        if (j == m) {
            results.push_back(i - j);
            j = lps[j - 1];
        } else if (i < n && text[i] != pattern[j]) {
            if (j != 0) {
                j = lps[j - 1];
            } else {
                i++;
            }
        }
    }
    return results;
}

int main() {
    ios_base::sync_with_stdio(false);
    cin.tie(nullptr);

    string text, pattern;
    getline(cin, text);
    getline(cin, pattern);

    auto matches = kmp_search(text, pattern);

    cout << matches.size() << "\n";
    for (size_t i = 0; i < matches.size(); i++) {
        if (i > 0) cout << " ";
        cout << matches[i];
    }
    cout << "\n";
    return 0;
}
