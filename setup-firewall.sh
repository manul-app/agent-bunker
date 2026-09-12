#!/bin/bash
set -e

# Network firewall rules to control access to servers, external databases, and local host resources
ALLOW_LOCAL_DB_ACCESS="${1:-${ALLOW_LOCAL_DB_ACCESS:-true}}"
ALLOW_LOCAL_DB_ACCESS="$(echo "$ALLOW_LOCAL_DB_ACCESS" | tr '[:upper:]' '[:lower:]')"

if command -v iptables >/dev/null 2>&1; then
    # Flush existing OUTPUT chain rules
    iptables -F OUTPUT 2>/dev/null || true

    # 1. Allow loopback interface (for local processes within the container)
    iptables -A OUTPUT -o lo -j ACCEPT

    # 2. Allow established and related connections
    iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

    # 3. Allow DNS queries (UDP and TCP on port 53)
    iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
    iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

    # 4. Allow HTTP (port 80) and HTTPS (port 443) for package managers, Claude API, web browsing, git
    iptables -A OUTPUT -p tcp --dport 80 -j ACCEPT
    iptables -A OUTPUT -p tcp --dport 443 -j ACCEPT

    # 5. Handle local network / host / local database access based on ALLOW_LOCAL_DB_ACCESS
    if [ "$ALLOW_LOCAL_DB_ACCESS" = "true" ] || [ "$ALLOW_LOCAL_DB_ACCESS" = "1" ] || [ "$ALLOW_LOCAL_DB_ACCESS" = "yes" ]; then
        echo "Firewall: Local database & host network access is ENABLED."
        # Allow connections to private/local networks (RFC 1918)
        # This covers host.docker.internal, docker bridge networks, and local dev services
        iptables -A OUTPUT -d 10.0.0.0/8 -j ACCEPT
        iptables -A OUTPUT -d 172.16.0.0/12 -j ACCEPT
        iptables -A OUTPUT -d 192.168.0.0/16 -j ACCEPT
        iptables -A OUTPUT -d 127.0.0.0/8 -j ACCEPT
    else
        echo "Firewall: Local network & host database access is BLOCKED."
        # Reject database ports even on local/private networks
        iptables -A OUTPUT -p tcp --dport 5432 -j REJECT --reject-with icmp-port-unreachable
        iptables -A OUTPUT -p tcp --dport 3306 -j REJECT --reject-with icmp-port-unreachable
        iptables -A OUTPUT -p tcp --dport 27017 -j REJECT --reject-with icmp-port-unreachable
        iptables -A OUTPUT -p tcp --dport 6379 -j REJECT --reject-with icmp-port-unreachable

        # Reject all connections to private networks and host gateway (except DNS which is accepted above)
        iptables -A OUTPUT -d 10.0.0.0/8 -j REJECT --reject-with icmp-port-unreachable
        iptables -A OUTPUT -d 172.16.0.0/12 -j REJECT --reject-with icmp-port-unreachable
        iptables -A OUTPUT -d 192.168.0.0/16 -j REJECT --reject-with icmp-port-unreachable
    fi

    # 6. Always BLOCK outgoing SSH connections to prevent remote server access
    iptables -A OUTPUT -p tcp --dport 22 -j REJECT --reject-with icmp-port-unreachable

    # 7. Always BLOCK outgoing connections to external databases on public IPs
    iptables -A OUTPUT -p tcp --dport 5432 -j REJECT --reject-with icmp-port-unreachable
    iptables -A OUTPUT -p tcp --dport 3306 -j REJECT --reject-with icmp-port-unreachable
    iptables -A OUTPUT -p tcp --dport 27017 -j REJECT --reject-with icmp-port-unreachable
    iptables -A OUTPUT -p tcp --dport 6379 -j REJECT --reject-with icmp-port-unreachable
fi
