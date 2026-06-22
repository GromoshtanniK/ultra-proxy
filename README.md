# ultra-proxy

A split-routing proxy you run in Docker. When the container is up, sing-box exposes
two entry points — a **TUN** interface (transparently captures traffic into it) and
an **HTTP/SOCKS5 proxy** port (plain listener). Each connection is then forwarded either **direct** or
through an **external HTTP(S) proxy**, based on its destination. The link to that
external proxy is plain HTTP by default, or HTTPS (TLS) when `EXT_TLS=true`.

```
   all outgoing traffic
   (TUN auto_route, or HTTP/SOCKS5 proxy port)
                │
                ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  ultra-proxy container (sing-box)                                           │
│                                                                             │
│  host in domains       (yours + remote list) ──┐                            │
│  ip   in CIDR subnets  (yours + remote list) ──┴──► external HTTP(S) proxy  │
│                                                                             │
│  everything else ──────────────────────────────────► DIRECT to internet     │
└─────────────────────────────────────────────────────────────────────────────┘
```

* Destination **host** in `config/rule-set/domains.json` → external proxy
* Destination **IP** in `config/rule-set/subnets.json` → external proxy
* Otherwise → direct

`domains.json` and `subnets.json` are your **own** extra domains and CIDRs, matched
on top of the remote rule-sets that sing-box downloads and refreshes automatically
(`block`, `geoblock`, `google_ai`, `telegram`, `youtube`, `cloudflare`, `cloudfront`,
`digitalocean`, `hetzner`, `hodca`, `ovh`). So you only need to add what isn't already covered.

## Run it

```bash
cp .env.example .env          # set EXT_SERVER / EXT_PORT (+ auth) of your external proxy
scripts/render-config.sh      # .env -> config/config.json
docker compose up -d
```

Edit the routing lists any time in `config/rule-set/domains.json` and
`subnets.json`, then `docker compose restart`. Changed `.env`? Re-render, then restart.

> Leave `EXT_SERVER` empty to send everything direct (useful for first testing).

## Using it

Once the container is up, traffic is already routed through the TUN interface —
nothing to configure on the client. Check the split routing works:

```bash
curl https://ifconfig.me
```

If you'd rather point an app at it explicitly, the same sing-box also exposes a
normal HTTP proxy on `PROXY_PORT` (default **8888**, HTTP and SOCKS5 on the same port):

```bash
curl -x http://127.0.0.1:8888 https://ifconfig.me
```
