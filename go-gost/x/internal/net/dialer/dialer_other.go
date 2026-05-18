//go:build !unix && !windows

package dialer

func bindDevice(network, address string, fd uintptr, ifceName string) error {
	return nil
}

func setMark(fd uintptr, mark int) error {
	return nil
}
