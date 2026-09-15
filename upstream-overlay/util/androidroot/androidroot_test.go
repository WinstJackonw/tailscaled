package androidroot

import (
	"reflect"
	"testing"
)

func TestParseServers(t *testing.T) {
	for _, tt := range []struct {
		text string
		conf bool
		want []string
	}{
		{"fe80::1%wlan0\n10.0.0.1\n", false, []string{"[fe80::1%wlan0]:53", "10.0.0.1:53"}},
		{"# comment\nnameserver 192.168.1.1 # router\nsearch lan\nnameserver 2001:4860:4860::8888\n", true, []string{"192.168.1.1:53", "[2001:4860:4860::8888]:53"}},
		{"nameserver 127.0.0.1\nnameserver ::1\nnameserver 0.0.0.0\nnameserver invalid", true, nil},
	} {
		if got := parseServers(tt.text, tt.conf); !reflect.DeepEqual(got, tt.want) {
			t.Errorf("parseServers(%q) = %v; want %v", tt.text, got, tt.want)
		}
	}
}
