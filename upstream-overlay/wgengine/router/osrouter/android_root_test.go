//go:build linux && !android

package osrouter

import (
	"testing"

	"tailscale.com/tsconst"
	"tailscale.com/version/distro"
)

func TestAndroidBypassesTailnetWithoutMainDefaultRoute(t *testing.T) {
	orig := getDistroFunc
	getDistroFunc = func() distro.Distro { return distro.Android }
	t.Cleanup(func() { getDistroFunc = orig })
	rules := ipRules()
	if len(rules) != 1 || !rules[0].Invert || rules[0].Mark != tsconst.LinuxBypassMarkNum || rules[0].Table != tailscaleRouteTable.Num {
		t.Fatalf("Android must route only non-bypass traffic through table 52, got %+v", rules)
	}
}
