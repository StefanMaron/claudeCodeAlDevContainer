#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

echo "=== Configuring network firewall ==="

# 1. Disable IPv6 entirely — prevents IPv6 firewall bypass
sysctl -w net.ipv6.conf.all.disable_ipv6=1
sysctl -w net.ipv6.conf.default.disable_ipv6=1
ip6tables -P INPUT DROP
ip6tables -P FORWARD DROP
ip6tables -P OUTPUT DROP

# 2. Extract Docker DNS rules BEFORE flushing
DOCKER_DNS_RULES=$(iptables-save -t nat | grep "127\.0\.0\.11" || true)

# Flush existing IPv4 rules
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
ipset destroy allowed-domains 2>/dev/null || true

# 3. Restore Docker internal DNS resolution
if [ -n "$DOCKER_DNS_RULES" ]; then
    echo "Restoring Docker DNS rules..."
    iptables -t nat -N DOCKER_OUTPUT 2>/dev/null || true
    iptables -t nat -N DOCKER_POSTROUTING 2>/dev/null || true
    echo "$DOCKER_DNS_RULES" | xargs -L 1 iptables -t nat
else
    echo "No Docker DNS rules to restore"
fi

# 4. Allow essential traffic before restrictions
# DNS — restricted to Docker internal resolver only (blocks DNS tunneling)
iptables -A OUTPUT -p udp --dport 53 -d 127.0.0.11 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -d 127.0.0.11 -j ACCEPT
iptables -A INPUT -p udp --sport 53 -s 127.0.0.11 -j ACCEPT
iptables -A INPUT -p tcp --sport 53 -s 127.0.0.11 -j ACCEPT
# Localhost
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# 5. Create ipset for allowed domains
ipset create allowed-domains hash:net

# 6. Resolve and add allowed domains
# Only Anthropic-owned services and VS Code infrastructure
for domain in \
    "api.anthropic.com" \
    "claude.ai" \
    "console.anthropic.com" \
    "statsig.anthropic.com" \
    "marketplace.visualstudio.com" \
    "vscode.blob.core.windows.net" \
    "update.code.visualstudio.com"; do
    echo "Resolving $domain..."
    ips=$(dig +noall +answer A "$domain" | awk '$4 == "A" {print $5}')
    if [ -z "$ips" ]; then
        echo "WARNING: Failed to resolve $domain (skipping)"
        continue
    fi

    while read -r ip; do
        if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo "  Adding $ip for $domain"
            ipset add allowed-domains "$ip" 2>/dev/null || true
        fi
    done < <(echo "$ips")
done

# 7. Allow Docker host gateway only (not the entire /24 subnet)
HOST_IP=$(ip route | grep default | cut -d" " -f3)
if [ -n "$HOST_IP" ]; then
    echo "Host gateway: $HOST_IP"
    iptables -A INPUT -s "$HOST_IP" -j ACCEPT
    iptables -A OUTPUT -d "$HOST_IP" -j ACCEPT
else
    echo "WARNING: Could not detect host gateway"
fi

# 8. Set default policies to DROP
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# 9. Allow established connections
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# 10. Allow only traffic to whitelisted domains
iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT

# 11. Log and reject everything else
iptables -A OUTPUT -j LOG --log-prefix "FIREWALL-BLOCKED: " --log-level 4 -m limit --limit 5/min
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

# 12. Harden sudo access
# Remove general sudo files (keep only firewall-specific rule)
find /etc/sudoers.d/ -type f ! -name '*-firewall' -delete 2>/dev/null || true
# Disable %sudo group in main sudoers file
sed -i 's/^%sudo.*/#&/' /etc/sudoers 2>/dev/null || true
# Remove container user from sudo group
CONTAINER_USER=$(stat -c '%U' /proc/1 2>/dev/null || echo "vscode")
deluser "$CONTAINER_USER" sudo 2>/dev/null || true

# 13. Install system-level git pre-push hook that blocks all pushes
mkdir -p /usr/share/git-core/templates/hooks
cat > /usr/share/git-core/templates/hooks/pre-push << 'HOOK'
#!/bin/sh
echo "ERROR: git push is blocked in this sandboxed environment."
exit 1
HOOK
chmod +x /usr/share/git-core/templates/hooks/pre-push
# Also install it in the workspace if a git repo exists
find /workspaces -name ".git" -type d -exec sh -c 'mkdir -p "$1/hooks" && cp /usr/share/git-core/templates/hooks/pre-push "$1/hooks/pre-push"' _ {} \; 2>/dev/null || true

# 14. Make the firewall script immutable (prevents modification even by root)
chattr +i /usr/local/bin/init-firewall.sh 2>/dev/null || true

echo "=== Firewall configured. Sudo hardened. ==="

# 15. Verify
echo "Verifying firewall..."
PASS=true

if curl --connect-timeout 5 https://github.com >/dev/null 2>&1; then
    echo "FAIL: github.com is reachable"
    PASS=false
else
    echo "PASS: github.com is blocked"
fi

if curl --connect-timeout 5 https://example.com >/dev/null 2>&1; then
    echo "FAIL: example.com is reachable"
    PASS=false
else
    echo "PASS: example.com is blocked"
fi

if curl --connect-timeout 5 https://api.anthropic.com >/dev/null 2>&1; then
    echo "PASS: api.anthropic.com is reachable"
else
    echo "WARN: api.anthropic.com is unreachable — Claude Code may not work"
fi

if [ "$PASS" = true ]; then
    echo "=== Firewall verification PASSED ==="
else
    echo "=== Firewall verification FAILED ==="
    exit 1
fi
