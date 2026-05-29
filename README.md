# 3X-UI 安装与全局代理配置

> 原项目：[MHSanaei/3x-ui](https://github.com/MHSanaei/3x-ui)

## 一、安装 x-ui

```bash
bash <(curl -Ls https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh)
```

安装完成后面板默认端口为 `54321`，首次登录后建议修改端口和密码。

---

## 二、Ubuntu 服务器全局代理（tun2socks）

将服务器所有流量通过 SOCKS5 代理转发，同时保持 SSH 和 x-ui 正常访问。

### 2.1 安装 unzip

```bash
apt install unzip -y
```

### 2.2 安装 tun2socks

优先从官方下载最新版本，若官方不可用则使用本仓库备份：

```bash
wget https://github.com/xjasonlyu/tun2socks/releases/latest/download/tun2socks-linux-amd64.zip \
  || wget https://raw.githubusercontent.com/PMJ520/vpn-3x-ui/master/backup/tun2socks-linux-amd64.zip

unzip tun2socks-linux-amd64.zip
mv tun2socks-linux-amd64 /usr/local/bin/tun2socks
chmod +x /usr/local/bin/tun2socks
```

### 2.3 下载 proxy-tun.sh 脚本

```bash
wget https://raw.githubusercontent.com/PMJ520/vpn-3x-ui/master/proxy-tun.sh -O /usr/local/bin/proxy-tun.sh
chmod +x /usr/local/bin/proxy-tun.sh
```

下载后编辑脚本，修改顶部的代理信息：

```bash
nano /usr/local/bin/proxy-tun.sh
```

```bash
PROXY="socks5://用户名:密码@代理IP:端口"
PROXY_IP="代理IP"   # 必须填 IP，不能填域名
```

> x-ui 面板和入站端口范围默认为 `2900:3000`，按实际情况修改脚本中对应的端口范围。

### 2.4 配置为系统服务（开机自启）

```bash
wget https://raw.githubusercontent.com/PMJ520/vpn-3x-ui/master/proxy-tun.service -O /etc/systemd/system/proxy-tun.service

systemctl daemon-reload
systemctl enable proxy-tun
systemctl start proxy-tun
```

### 2.5 常用命令

```bash
systemctl status proxy-tun    # 查看状态
systemctl stop proxy-tun      # 停止
systemctl restart proxy-tun   # 重启
journalctl -u proxy-tun -f    # 查看日志
```

### 2.6 验证代理是否生效

```bash
curl https://api.ipify.org
# 返回代理服务器 IP 即为成功
```

---

## 三、x-ui Xray 配置（避免双重代理）

x-ui 作为代理服务器，其出站流量不应再走 tun0，否则会造成双重代理。通过 xray 的 `sockopt mark` 功能让出站流量直接绕过 tun0。

### 3.1 修改 direct outbound 配置

进入 x-ui 面板 → **Xray Configs** → **Outbounds** → 编辑 `direct`，将配置改为：

```json
{
  "protocol": "freedom",
  "settings": {
    "domainStrategy": "AsIs",
    "finalRules": [
      {
        "action": "allow",
        "ip": [
          "geoip:private"
        ]
      }
    ]
  },
  "streamSettings": {
    "sockopt": {
      "mark": 255
    }
  },
  "tag": "direct"
}
```

保存后点击 **Restart Xray**。

### 3.2 流量分流说明

| 流量类型 | 处理方式 |
|---|---|
| SSH（端口 22） | 绕过 tun0，走原始网关 |
| x-ui 面板和入站（2900-3000） | 绕过 tun0，走原始网关 |
| xray 出站（替客户端代理） | xray mark 255，走原始网关 |
| 服务器自身其他流量 | 走 tun0 → SOCKS5 代理 |

---

## 四、注意事项

- `PROXY_IP` 必须填写 IP 地址，不能是域名，防止 DNS 解析走 tun0 造成死循环
- x-ui 面板端口和入站端口范围需与脚本中端口范围保持一致
- 如果 SSH 断连，通过云服务商控制台或云助手执行以下命令恢复：
  ```bash
  pkill tun2socks; ip route del default dev tun0 2>/dev/null; ip tuntap del mode tun dev tun0 2>/dev/null
  ```
- 服务器重启后 systemd 会自动重启代理服务
