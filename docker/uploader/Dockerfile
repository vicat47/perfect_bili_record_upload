FROM redis:6.2.17 AS builder

FROM debian:stable-slim

# 安装基础文件
RUN apt update && \
    apt install -y wget xz-utils jq

# 安装应用
COPY --from=builder /usr/local/bin/redis-cli /usr/local/bin/

RUN cd /tmp/ || exit 1 && \
    wget -O biliup.tar.xz https://github.com/biliup/biliup-rs/releases/download/v0.2.2/biliupR-v0.2.2-x86_64-linux.tar.xz && \
    tar -xvf biliup.tar.xz && \
    mv biliupR-v0.2.2-x86_64-linux/biliup /usr/local/bin/

COPY ./docker-entrypoint.sh /docker-entrypoint.sh

WORKDIR /opt/uploader
ENTRYPOINT [ "/docker-entrypoint.sh" ]
