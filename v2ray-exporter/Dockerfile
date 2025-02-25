FROM alpine:3.21.3

RUN apk add --no-cache wget && \
    ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then arch="amd64"; elif [ "$ARCH" = "aarch64" ]; then arch="arm64"; else echo "Unsupported architecture" && exit 1; fi && \
    wget -O /v2ray-exporter https://github.com/wi1dcard/v2ray-exporter/releases/download/v0.6.0/v2ray-exporter_linux_${arch} && \
    chmod +x /v2ray-exporter && \
    apk del wget

CMD ["/v2ray-exporter", "--v2ray-endpoint", "xray:54321"]
