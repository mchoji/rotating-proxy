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


## License

This project is licensed under MIT license. See [LICENSE](LICENSE) for more information.


## Acknowledgments

This project was inspired on [rotating-proxy](https://github.com/mattes/rotating-proxy) by @mattes.
