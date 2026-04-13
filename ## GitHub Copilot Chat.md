## GitHub Copilot Chat

- Extension: 0.43.0 (prod)
- VS Code: 1.115.0 (41dd792b5e652393e7787322889ed5fdc58bd75b)
- OS: win32 10.0.26200 x64
- GitHub Account: azzam1122112-dot

## Network

User Settings:
```json
  "http.systemCertificatesNode": true,
  "github.copilot.advanced.debug.useElectronFetcher": true,
  "github.copilot.advanced.debug.useNodeFetcher": false,
  "github.copilot.advanced.debug.useNodeFetchFetcher": true
```

Connecting to https://api.github.com:
- DNS ipv4 Lookup: 20.233.83.146 (6 ms)
- DNS ipv6 Lookup: Error (6 ms): getaddrinfo ENOTFOUND api.github.com
- Proxy URL: None (1 ms)
- Electron fetch (configured): HTTP 200 (77 ms)
- Node.js https: HTTP 200 (209 ms)
- Node.js fetch: HTTP 200 (597 ms)

Connecting to https://api.githubcopilot.com/_ping:
- DNS ipv4 Lookup: 140.82.113.22 (34 ms)
- DNS ipv6 Lookup: Error (7 ms): getaddrinfo ENOTFOUND api.githubcopilot.com
- Proxy URL: None (14 ms)
- Electron fetch (configured): HTTP 200 (849 ms)
- Node.js https: HTTP 200 (574 ms)
- Node.js fetch: HTTP 200 (674 ms)

Connecting to https://copilot-proxy.githubusercontent.com/_ping:
- DNS ipv4 Lookup: 20.250.119.64 (120 ms)
- DNS ipv6 Lookup: 64:ff9b::14fa:7740 (128 ms)
- Proxy URL: None (16 ms)
- Electron fetch (configured): HTTP 200 (504 ms)
- Node.js https: HTTP 200 (462 ms)
- Node.js fetch: HTTP 200 (570 ms)

Connecting to https://mobile.events.data.microsoft.com: HTTP 404 (274 ms)
Connecting to https://dc.services.visualstudio.com: HTTP 404 (980 ms)
Connecting to https://copilot-telemetry.githubusercontent.com/_ping: HTTP 200 (1373 ms)
Connecting to https://copilot-telemetry.githubusercontent.com/_ping: HTTP 200 (765 ms)
Connecting to https://default.exp-tas.com: HTTP 400 (875 ms)

Number of system certificates: 88

## Documentation

In corporate networks: [Troubleshooting firewall settings for GitHub Copilot](https://docs.github.com/en/copilot/troubleshooting-github-copilot/troubleshooting-firewall-settings-for-github-copilot).