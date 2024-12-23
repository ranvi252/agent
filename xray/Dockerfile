FROM teddysun/xray:24.12.18

RUN apk update && apk add curl wget

COPY entrypoint.sh entrypoint.sh

RUN wget -O /usr/share/xray/geoip.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat
RUN wget -O /usr/share/xray/geosite.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat
RUN wget -O /usr/share/xray/geoip_IR.dat https://github.com/chocolate4u/Iran-v2ray-rules/releases/latest/download/geoip.dat
RUN wget -O /usr/share/xray/geosite_IR.dat https://github.com/chocolate4u/Iran-v2ray-rules/releases/latest/download/geosite.dat

CMD ["./entrypoint.sh"]
