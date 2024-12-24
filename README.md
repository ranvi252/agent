# Compass VPN Agent


## Features

1. One-command VPN setup and remote monitoring.
2. Send metrics and generated configuration links to a central dashboard.
3. Collect vital VM metrics, such as CPU, memory, and traffic.
4. Automatic Cloudflare DNS management.
5. Support for direct configurations or configurations behind the Cloudflare CDN proxy.
6. Automatic certificate generation for TLS configurations (using ZeroSSL or Let's Encrypt).
7. Support for Warp and direct outbound connections.
8. Automatic discovery of the best Warp endpoint with auto-rotation.
9. Create a variety of VPN configurations.
10. Automatic updates.
11. Automatic configuration rotation.
12. Automatic blocking of: torrents, Iranian websites, Ads, Malware, and Phishing (with automatic file download).
13. Support for free Grafana Cloud or Pushgateway for metric collection and dashboard integration.
14. Configuration self-testing using Xray-Knife.
15. And more...


## Requirements

- **VPS Architecture**: **AMD64** or **ARM64** _(recommended: 2 vCPUs and 2GB RAM)_.
- **Supported OS**: **Ubuntu (20+)**, **Debian (10+)**, **Fedora (37+)**.
- `git` and `curl` packages installed on the server:
```bash
sudo apt update -q && sudo apt install -yq git curl
```


## Services

### `xray-config`
Creates `config.json`, monitors configurations, and export Xray configurations via `/metrics` path.

### `xray`
Reads `config.json` from the **xray-config** service and runs the xray-core.

### `v2ray-exporter`
Exports V2Ray configuration metrics.

### `node-exporter`
Prometheus Node Exporter that collects all critical metrics of the agent machine.

### `metric-forwarder`
Reads metrics from `xray-config`, `node-exporter`, and `v2ray-exporter` services and pushes them to a remote manager `Pushgateway` service or `Grafana Cloud Prometheus` endpoint.

## Setup Manager
Please follow [this tutorial](https://github.com/compassvpn/manager) to create a manager. You can choose between the following options:
- Grafana Cloud
- Hosted Grafana + Prometheus

Ensure you obtain the authentication values from the manager setup. These values will be required to be included in the `env_file` of the agent.


# How to run

The following services must be run on a VPS you intend to use as a VPN server.

## Clone

1. ```bash
      git clone https://github.com/compassvpn/agent.git
      ```
2. ```bash
      cd agent
      ```

## Configure `env_file`

1. ```bash 
      cp env_file.example env_file
      ```
2. Set `METRIC_PUSH_METHOD` to either `pushgateway` or `grafana_cloud`, based on your chosen Manager option.

3. if `METRIC_PUSH_METHOD=grafana_agent` _(set during the manager setup: [Option 1](https://github.com/compassvpn/manager?tab=readme-ov-file#option-1-use-garafana-cloud))_
      - set `GRAFANA_AGENT_REMOTE_WRITE_URL` _(Grafana remote URL)_
      - set `GRAFANA_AGENT_REMOTE_WRITE_USER` _(Grafana user)_
      - set `GRAFANA_AGENT_REMOTE_WRITE_PASSWORD` _(Grafana token password)_

4. if `METRIC_PUSH_METHOD=pushgateway` _(set during the manager setup: [Option 2](https://github.com/compassvpn/manager?tab=readme-ov-file#option-2-deploy-your-own-server))_
      - set `PUSHGATEWAY_URL` _(pushgateway URL)_
      - set `PUSHGATEWAY_AUTH_USER` _(pushgateway basic auth user)_
      - set `PUSHGATEWAY_AUTH_PASSWORD` _(pushgateway basic auth password)_

5. Set `DONOR=noname` _(used as a label in Prometheus metrics)_.

6. Set `REDEPLOY_INTERVAL` _(resets `IDENTIFIER` and generates new configurations at each interval, e.g., `1d` for 1 day, `14d` for every two weeks)_.

7. Set `IPINFO_API_TOKEN` _(Optional, signup at [ipinfo](https://ipinfo.io/signup))_

8. Set `CF_ENABLE` to:
      - `true` to include Cloudflare CDN configuration links alongside other configs.
      - `false` to skip generating Cloudflare CDN configs.

9. Set `CF_ONLY` to:
      - `true` if the server's IP is filtered or not clean.
      - `false` to allow direct configurations without Cloudflare.

10. Configure Cloudflare `CF_API_TOKEN` and `CF_ZONE_ID`
      - `CF_API_TOKEN`: Create this token for one zone at [Cloudflare API Token Setup](https://developers.cloudflare.com/fundamentals/api/get-started/create-token/).
      - `CF_ZONE_ID`: Use the Zone ID selected when creating the API token.

11. Set `SSL_PROVIDER` to `letsencrypt` or `zerossl` (depending on your preferred SSL certificate provider).

12. Set `XRAY_OUTBOUND` to:
      - `direct` for direct outbound connections.
      - `warp` for [WARP](https://one.one.one.one) outbound connections.

13. Set `XRAY_INBOUNDS` to your desired inbound configurations, as defined in inbounds.json.
      
      Supported Inbounds:
      - `VLess-TCP-TLS-Direct`
      - `VLess-HU-TLS-CDN`
      - _(Default when not set: `VLess-TCP-TLS-Direct,VLess-HU-TLS-CDN`)_

14. Set `AUTO_UPDATE` to:
      - `on` to enable automatic updates.
      - `off` to disable automatic updates _(default if not provided or commented out)_.


## Commands

### Bootstrap: _(first time)_
```bash
./bootstrap.sh
```

### Rebuild and restart all services:
```bash
./restart.sh
```

### Update:
```bash
./update.sh && sleep 1 && ./restart.sh
```

### Show Logs:
```bash
./logs.sh
```
