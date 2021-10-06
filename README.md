# rotating-proxy
Rotating proxy with Docker

## Introduction

With this docker image, one should be able to use lots of different IP addresses
from one single endpoint for your client. Load-balancing is supported by HAproxy.

```none
                        Docker Container
               ---------------------------------
                        <-> Polipo 1 <-> Proxy 1
Client <---->  HAproxy  <-> Polipo 2 <-> Proxy 2
                        <-> Polipo n <-> Proxy n
```

## Getting started

Clone repository

```sh
git clone https://github.com/mchoji/rotating-proxy.git
```

Run `docker-compose` from inside the directory

```sh
docker-compose up
```

You can run the container in background as well

```sh
docker-compose -d up
```

This will expose a web page for monitoring proxies at http://127.0.0.1:4444/haproxy?stats
and an HTTP proxy at http://127.0.0.1:5566.

You can test proxy with

```sh
curl --proxy 127.0.0.1:5566 https://api.ipify.org
```

## Operation Modes

There are two implemented operation modes:
  - Tor
  - Proxy list

The behaviour of the application depends on the variables defined at [config.env](config.env), which can be overridden by shell variables with the same name.

```sh
pool_size=25
test_url=https://api.ipify.org
ssl_verify=true
mode=tor
```

`pool_size` defines the number of backend proxies to be used. `test_url` is used during operation to check if a given proxy is responding.
`ssl_verify` defines if certificates should be verified or not. `mode` dictates the operation mode (acceptable values are `tor` or `list`).

If `mode=list` is used, a file named `proxy.lst` should exist at [config](config). The file should contain a list of proxies, one per line, in the format `[scheme]://[host]:[port]`, for instance `socks5://127.0.0.1`. It is possible to use `http`, `socks4` and `socks5` proxies, even mixed in the same list.


## License

This project is licensed under MIT license. See [LICENSE](LICENSE) for more information.


## Acknowledgments

This project was inspired on [rotating-proxy](https://github.com/mattes/rotating-proxy) by @mattes.
