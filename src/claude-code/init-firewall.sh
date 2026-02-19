#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

echo "Configuring network firewall..."

# 1. Extract Docker DNS rules BEFORE flushing
DOCKER_DNS_RULES=$(iptables-save -t nat | grep "127\.0\.0\.11" || true)

# Flush existing rules
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
ipset destroy allowed-domains 2>/dev/null || true

# 2. Restore Docker internal DNS resolution
if [ -n "$DOCKER_DNS_RULES" ]; then
    echo "Restoring Docker DNS rules..."
    iptables -t nat -N DOCKER_OUTPUT 2>/dev/null || true
    iptables -t nat -N DOCKER_POSTROUTING 2>/dev/null || true
    echo "$DOCKER_DNS_RULES" | xargs -L 1 iptables -t nat
else
    echo "No Docker DNS rules to restore"
fi

# 3. Allow essential traffic before restrictions
# DNS
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A INPUT -p udp --sport 53 -j ACCEPT
# Localhost
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# 4. Create ipset for allowed domains
ipset create allowed-domains hash:net

# 5. Resolve and add allowed domains
# Anthropic services (Claude Code API, auth, telemetry)
# VS Code services (extensions, updates)
for domain in \
    "api.anthropic.com" \
    "claude.ai" \
    "console.anthropic.com" \
    "sentry.io" \
    "statsig.anthropic.com" \
    "statsig.com" \
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

# 6. Allow Docker host network
HOST_IP=$(ip route | grep default | cut -d" " -f3)
if [ -n "$HOST_IP" ]; then
    HOST_NETWORK=$(echo "$HOST_IP" | sed "s/\.[0-9]*$/.0\/24/")
    echo "Host network: $HOST_NETWORK"
    iptables -A INPUT -s "$HOST_NETWORK" -j ACCEPT
    iptables -A OUTPUT -d "$HOST_NETWORK" -j ACCEPT
else
    echo "WARNING: Could not detect host network"
fi

# 7. Set default policies to DROP
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# 8. Allow established connections
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# 9. Allow only traffic to whitelisted domains
iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT

# 10. Reject everything else with immediate feedback
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

# 11. Remove general sudo access — keep only the firewall-specific rule
find /etc/sudoers.d/ -type f ! -name '*-firewall' -delete 2>/dev/null || true

echo "Firewall configured. General sudo access removed."

# 12. Verify
echo "Verifying firewall..."
if curl --connect-timeout 5 https://github.com >/dev/null 2>&1; then
    echo "WARNING: Firewall verification failed — github.com is reachable"
else
    echo "PASS: github.com is blocked"
fi

if curl --connect-timeout 5 https://api.anthropic.com >/dev/null 2>&1; then
    echo "PASS: api.anthropic.com is reachable"
else
    echo "WARNING: api.anthropic.com is unreachable — Claude Code may not work"
fi

echo "Firewall setup complete."
