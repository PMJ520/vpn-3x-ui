#!/bin/bash

PROXY="socks5://CSkWuPyukcFr:dWfc3JAupd@130.12.42.121:443"
PROXY_IP="130.12.42.121"
DEFAULT_GW=$(ip route | grep default | awk '{print $3}' | head -1)
DEFAULT_IFACE=$(ip route | grep default | awk '{print $5}' | head -1)

stop_proxy() {
    echo "关闭代理..."
    pkill tun2socks 2>/dev/null

    iptables -t mangle -D OUTPUT -p tcp --sport 22 -j MARK --set-mark 1 2>/dev/null
    iptables -t mangle -D OUTPUT -p tcp --dport 22 -j MARK --set-mark 1 2>/dev/null
    iptables -t mangle -D PREROUTING -p tcp --dport 22 -j MARK --set-mark 1 2>/dev/null
    iptables -t mangle -D OUTPUT -p tcp --sport 2900:3000 -j MARK --set-mark 1 2>/dev/null
    iptables -t mangle -D OUTPUT -p tcp --dport 2900:3000 -j MARK --set-mark 1 2>/dev/null
    iptables -t mangle -D PREROUTING -p tcp --dport 2900:3000 -j MARK --set-mark 1 2>/dev/null

    ip rule del fwmark 1 table 100 2>/dev/null
    ip rule del fwmark 255 table 100 2>/dev/null
    ip route flush table 100 2>/dev/null
    ip route del default dev tun0 2>/dev/null
    ip tuntap del mode tun dev tun0 2>/dev/null

    echo "代理已关闭"
}

start_proxy() {
    if [ -z "$DEFAULT_GW" ]; then
        echo "错误：无法获取默认网关"
        exit 1
    fi

    echo "默认网关: $DEFAULT_GW ($DEFAULT_IFACE)"
    echo "代理服务器: $PROXY_IP"

    # 创建 TUN 网卡
    ip tuntap add mode tun dev tun0
    ip addr add 198.18.0.1/15 dev tun0
    ip link set dev tun0 up

    # 建立旁路路由表 100（走原始网关）
    ip route add default via "$DEFAULT_GW" dev "$DEFAULT_IFACE" table 100
    # SSH 流量（mark 1）→ 走原始网关
    ip rule add fwmark 1 table 100 priority 100
    # xray direct 出站流量（mark 255）→ 走原始网关
    ip rule add fwmark 255 table 100 priority 50

    # SSH 端口（22）不走代理
    iptables -t mangle -A OUTPUT -p tcp --sport 22 -j MARK --set-mark 1
    iptables -t mangle -A OUTPUT -p tcp --dport 22 -j MARK --set-mark 1
    iptables -t mangle -A PREROUTING -p tcp --dport 22 -j MARK --set-mark 1

    # x-ui 面板 + 入站端口（2900-3000）不走代理
    iptables -t mangle -A OUTPUT -p tcp --sport 2900:3000 -j MARK --set-mark 1
    iptables -t mangle -A OUTPUT -p tcp --dport 2900:3000 -j MARK --set-mark 1
    iptables -t mangle -A PREROUTING -p tcp --dport 2900:3000 -j MARK --set-mark 1

    # 其余流量走 tun0
    ip route add default dev tun0 metric 1

    echo "代理已启动，按 Ctrl+C 停止..."

    trap stop_proxy INT TERM

    # -interface 绑定物理网卡，tun2socks 自身连代理不走 tun0
    tun2socks -device tun0 -proxy "$PROXY" -interface "$DEFAULT_IFACE"

    stop_proxy
}

case "$1" in
    stop) stop_proxy ;;
    *)    start_proxy ;;
esac
