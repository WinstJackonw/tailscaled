// Package androidroot adapts the static Linux binary to rooted Android.
package androidroot

import (
	"context"
	"net"
	"net/netip"
	"os"
	"os/exec"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"tailscale.com/version/distro"
)

// Configure is called before the combined binary dispatches the CLI or daemon.
// Android's netd owns system DNS; a Linux Go resolver cannot use Bionic/netd.
func Configure() {
	if distro.Get() != distro.Android {
		return
	}
	if os.Getenv("SSL_CERT_DIR") == "" {
		os.Setenv("SSL_CERT_DIR", "/apex/com.android.conscrypt/cacerts:/system/etc/security/cacerts")
	}
	if os.Getenv("TS_LOGS_DIR") == "" {
		const logs = "/data/adb/tailscale/run"
		if os.MkdirAll(logs, 0700) == nil {
			os.Setenv("TS_LOGS_DIR", logs)
		}
	}
	// Keep the pointer: packages may already hold net.DefaultResolver.
	net.DefaultResolver.PreferGo = true
	net.DefaultResolver.Dial = dialDNS
}

var dnsCache struct {
	sync.Mutex
	until time.Time
	servers []string
}
var nextServer atomic.Uint64

func parseServers(text string, resolvConf bool) []string {
	var servers []string
	for _, line := range strings.Split(text, "\n") {
		fields := strings.Fields(line)
		if resolvConf {
			if len(fields) < 2 || fields[0] != "nameserver" {
				continue
			}
			fields = fields[1:2]
		}
		for _, field := range fields {
			if addr, err := netip.ParseAddr(field); err == nil && !addr.IsUnspecified() && !addr.IsLoopback() {
				servers = append(servers, net.JoinHostPort(addr.String(), "53"))
			}
		}
	}
	return servers
}

func dnsServers(ctx context.Context) []string {
	dnsCache.Lock()
	defer dnsCache.Unlock()
	if time.Now().Before(dnsCache.until) {
		return dnsCache.servers
	}
	// An explicit module configuration takes precedence over netd properties.
	data, _ := os.ReadFile("/data/adb/tailscale/etc/resolv.conf")
	servers := parseServers(string(data), true)
	if len(servers) == 0 {
		for _, key := range []string{"net.dns1", "net.dns2", "net.dns3", "net.dns4"} {
			queryCtx, cancel := context.WithTimeout(ctx, time.Second)
			data, _ := exec.CommandContext(queryCtx, "/system/bin/getprop", key).Output()
			cancel()
			servers = append(servers, parseServers(string(data), false)...)
		}
	}
	// Recent Android versions may not publish net.dns* properties. Users can
	// override these bootstrap resolvers in the module's resolv.conf above.
	if len(servers) == 0 {
		servers = []string{"1.1.1.1:53", "8.8.8.8:53"}
	}
	dnsCache.servers = servers
	dnsCache.until = time.Now().Add(5 * time.Second)
	return servers
}

func dialDNS(ctx context.Context, network, _ string) (net.Conn, error) {
	servers := dnsServers(ctx)
	server := servers[(nextServer.Add(1)-1)%uint64(len(servers))]
	// Preserve TCP for truncated replies. Leave these sockets unmarked so
	// Android selects its current underlying network via netd's policy rules.
	return (&net.Dialer{Timeout: 3 * time.Second}).DialContext(ctx, network, server)
}
