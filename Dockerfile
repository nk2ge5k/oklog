FROM golang:1.21 AS builder

WORKDIR /oklog
COPY . .

RUN apt-get update && apt-get install -y tzdata git

RUN echo "UTC" > /etc/timezone
RUN ln -sf /usr/share/zoneinfo/UTC /etc/localtime
RUN dpkg-reconfigure -f noninteractive tzdata

RUN make build

FROM scratch

EXPOSE 7659 7651 7653 7650

COPY --from=builder /oklog/build/oklog.linux.amd64 /usr/local/bin/oklog
COPY --from=builder /usr/share/zoneinfo /usr/share/zoneinfo
COPY --from=builder /etc/timezone /etc/timezone

ENV TZ=UTC

USER 1000

ENTRYPOINT ["oklog"]
