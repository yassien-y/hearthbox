# Shared server-level settings. Included in every site server block.

proxy_read_timeout 300s;

if ($backend = "") { return 404; }

location / {
    include conf.d/proxy.inc;
}
