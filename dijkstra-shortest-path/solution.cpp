#include <iostream>
#include <vector>
#include <queue>
#include <limits>

using namespace std;

int main() {
    ios_base::sync_with_stdio(false);
    cin.tie(nullptr);

    int n, m;
    cin >> n >> m;

    vector<vector<pair<int, long long>>> adj(n + 1);
    for (int i = 0; i < m; i++) {
        int u, v;
        long long w;
        cin >> u >> v >> w;
        adj[u].emplace_back(v, w);
    }

    const long long INF = numeric_limits<long long>::max();
    vector<long long> dist(n + 1, INF);
    dist[1] = 0;

    // min-heap: (distance, node)
    priority_queue<pair<long long, int>, vector<pair<long long, int>>, greater<>> pq;
    pq.emplace(0, 1);

    while (!pq.empty()) {
        auto [d, u] = pq.top();
        pq.pop();
        if (d > dist[u]) continue;
        for (auto [v, w] : adj[u]) {
            long long new_dist = dist[u] + w;
            if (new_dist < dist[v]) {
                dist[v] = new_dist;
                pq.emplace(new_dist, v);
            }
        }
    }

    cout << (dist[n] == INF ? -1 : dist[n]) << "\n";
    return 0;
}
