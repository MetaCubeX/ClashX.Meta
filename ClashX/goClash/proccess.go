package main

import (
	"encoding/binary"
	"fmt"
	"net/netip"
	"strconv"
	"strings"
	"syscall"
	"unsafe"
)

const (
	procpidpathinfo     = 0xb
	procpidpathinfosize = 1024
	proccallnumpidinfo  = 0x2
)

var structSize = func() int {
	value, _ := syscall.Sysctl("kern.osrelease")
	major, _, _ := strings.Cut(value, ".")
	n, _ := strconv.ParseInt(major, 10, 64)
	switch true {
	case n >= 22:
		return 408
	default:
		// from darwin-xnu/bsd/netinet/in_pcblist.c:get_pcblist_n
		// size/offset are round up (aligned) to 8 bytes in darwin
		// rup8(sizeof(xinpcb_n)) + rup8(sizeof(xsocket_n)) +
		// 2 * rup8(sizeof(xsockbuf_n)) + rup8(sizeof(xsockstat_n))
		return 384
	}
}()

func GetTcpNetList() string {
	value, err := syscall.Sysctl("net.inet.tcp.pcblist_n")
	if err != nil {
		return ""
	}

	buf := []byte(value)
	itemSize := structSize
	// tcp
	// rup8(sizeof(xtcpcb_n))
	itemSize += 208

	result := ""
	for i := 24; i+itemSize <= len(buf); i += itemSize {
		// offset of xinpcb_n and xsocket_n
		inp, so := i, i+104
		srcPort := binary.BigEndian.Uint16(buf[inp+18 : inp+20])
		// xinpcb_n.inp_vflag
		flag := buf[inp+44]

		var srcIP netip.Addr
		switch {
		case flag&0x1 > 0:
			// ipv4
			srcIP = netip.AddrFrom4([4]byte(buf[inp+76 : inp+80]))
		case flag&0x2 > 0:
			// ipv6
			srcIP = netip.AddrFrom16([16]byte(buf[inp+64 : inp+80]))
		default:
			continue
		}
		pid := readNativeUint32(buf[so+68 : so+72])
		result += fmt.Sprintf("%s %d %d\n", srcIP, srcPort, pid)
	}
	return result
}

func GetUDpList() string {
	value, err := syscall.Sysctl("net.inet.udp.pcblist_n")
	if err != nil {
		return ""
	}

	buf := []byte(value)
	itemSize := structSize
	result := ""

	for i := 24; i+itemSize <= len(buf); i += itemSize {
		// offset of xinpcb_n and xsocket_n
		inp, so := i, i+104
		srcPort := binary.BigEndian.Uint16(buf[inp+18 : inp+20])
		// xinpcb_n.inp_vflag
		flag := buf[inp+44]
		var srcIP netip.Addr
		switch {
		case flag&0x1 > 0:
			// ipv4
			srcIP = netip.AddrFrom4([4]byte(buf[inp+76 : inp+80]))
		case flag&0x2 > 0:
			// ipv6
			srcIP = netip.AddrFrom16([16]byte(buf[inp+64 : inp+80]))
		default:
			continue
		}

		pid := readNativeUint32(buf[so+68 : so+72])
		result += fmt.Sprintf("%s %d %d\n", srcIP, srcPort, pid)
	}
	return result
}

func readNativeUint32(b []byte) uint32 {
	return *(*uint32)(unsafe.Pointer(&b[0]))
}
