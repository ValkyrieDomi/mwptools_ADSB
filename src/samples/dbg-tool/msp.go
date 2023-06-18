package main

import (
	"go.bug.st/serial"
	"log"
	"net"
	"strings"
	"time"
)

const (
	msp_FC_VARIANT = 2
	msp_FC_VERSION = 3
	msp_REBOOT     = 68
	msp_DEBUG      = 253
)

const (
	state_INIT = iota
	state_M
	state_DIRN
	state_LEN
	state_CMD
	state_DATA
	state_CRC

	state_X_HEADER2
	state_X_FLAGS
	state_X_ID1
	state_X_ID2
	state_X_LEN1
	state_X_LEN2
	state_X_DATA
	state_X_CHECKSUM
)

type SerDev interface {
	Read(buf []byte) (int, error)
	Write(buf []byte) (int, error)
	Close() error
}

type MSPSerial struct {
	SerDev
}

func crc8_dvb_s2(crc byte, a byte) byte {
	crc ^= a
	for i := 0; i < 8; i++ {
		if (crc & 0x80) != 0 {
			crc = (crc << 1) ^ 0xd5
		} else {
			crc = crc << 1
		}
	}
	return crc
}

func (m *MSPSerial) msp_reader(c0 chan SChan) {
	inp := make([]byte, 128)
	var count = uint16(0)
	var crc = byte(0)
	var sc SChan

	n := state_INIT
	for {
		nb, err := m.Read(inp)
		if err == nil && nb > 0 {
			for i := 0; i < nb; i++ {
				switch n {
				case state_INIT:
					if inp[i] == '$' {
						n = state_M
						sc.ok = false
						sc.len = 0
						sc.cmd = 0
					}
				case state_M:
					if inp[i] == 'M' {
						n = state_DIRN
					} else if inp[i] == 'X' {
						n = state_X_HEADER2
					} else {
						n = state_INIT
					}
				case state_DIRN:
					if inp[i] == '!' {
						n = state_LEN
					} else if inp[i] == '>' {
						n = state_LEN
						sc.ok = true
					} else {
						n = state_INIT
					}

				case state_X_HEADER2:
					if inp[i] == '!' {
						n = state_X_FLAGS
					} else if inp[i] == '>' {
						n = state_X_FLAGS
						sc.ok = true
					} else {
						n = state_INIT
					}

				case state_X_FLAGS:
					crc = crc8_dvb_s2(0, inp[i])
					n = state_X_ID1

				case state_X_ID1:
					crc = crc8_dvb_s2(crc, inp[i])
					sc.cmd = uint16(inp[i])
					n = state_X_ID2

				case state_X_ID2:
					crc = crc8_dvb_s2(crc, inp[i])
					sc.cmd |= (uint16(inp[i]) << 8)
					n = state_X_LEN1

				case state_X_LEN1:
					crc = crc8_dvb_s2(crc, inp[i])
					sc.len = uint16(inp[i])
					n = state_X_LEN2

				case state_X_LEN2:
					crc = crc8_dvb_s2(crc, inp[i])
					sc.len |= (uint16(inp[i]) << 8)
					if sc.len > 0 {
						n = state_X_DATA
						count = 0
						sc.data = make([]byte, sc.len)
					} else {
						n = state_X_CHECKSUM
					}
				case state_X_DATA:
					crc = crc8_dvb_s2(crc, inp[i])
					sc.data[count] = inp[i]
					count++
					if count == sc.len {
						n = state_X_CHECKSUM
					}

				case state_X_CHECKSUM:
					ccrc := inp[i]
					if crc != ccrc {
						log.Printf("CRC error on %d\n", sc.cmd)
					} else {
						c0 <- sc
					}
					n = state_INIT

				case state_LEN:
					sc.len = uint16(inp[i])
					crc = inp[i]
					n = state_CMD
				case state_CMD:
					sc.cmd = uint16(inp[i])
					crc ^= inp[i]
					if sc.len == 0 {
						n = state_CRC
					} else {
						sc.data = make([]byte, sc.len)
						n = state_DATA
						count = 0
					}
				case state_DATA:
					sc.data[count] = inp[i]
					crc ^= inp[i]
					count++
					if count == sc.len {
						n = state_CRC
					}
				case state_CRC:
					ccrc := inp[i]
					if crc != ccrc {
						log.Printf("CRC error on %d\n", sc.cmd)
					} else {
						c0 <- sc
					}
					n = state_INIT
				}
			}
		} else {
			if err != nil {
				log.Printf("Read error: %s\n", err)
			}
			m.SerDev.Close()
			c0 <- SChan{ok: false, cmd: 0xffff}
			return
		}
	}
}

func encode_msp(cmd byte, payload []byte) []byte {
	var paylen byte
	if len(payload) > 0 {
		paylen = byte(len(payload))
	}
	buf := make([]byte, 6+paylen)
	buf[0] = '$'
	buf[1] = 'M'
	buf[2] = '<'
	buf[3] = paylen
	buf[4] = cmd
	if paylen > 0 {
		copy(buf[5:], payload)
	}
	crc := byte(0)
	for _, b := range buf[3:] {
		crc ^= b
	}
	buf[5+paylen] = crc
	return buf
}

func (m *MSPSerial) MSPReboot() {
	rb := encode_msp(msp_REBOOT, nil)
	m.Write(rb)
}

func (m *MSPSerial) MSPVersion() {
	rb := encode_msp(msp_FC_VERSION, nil)
	m.Write(rb)
}

func (m *MSPSerial) MSPVariant() {
	rb := encode_msp(msp_FC_VARIANT, nil)
	m.Write(rb)
}

func MSPRunner(name string, baud int, c0 chan SChan) (*MSPSerial, error) {
	var m *MSPSerial
	h, p, err := net.SplitHostPort(name)
	if err == nil && h != "" && p != "" {
		var conn net.Conn
		addr, nerr := net.ResolveTCPAddr("tcp", name)
		if nerr == nil {
			conn, err = net.DialTCP("tcp", nil, addr)
			m = &MSPSerial{conn}
		} else {
			err = nerr
		}
	} else {
		mode := &serial.Mode{
			BaudRate: baud,
		}
		pt, perr := serial.Open(name, mode)
		if perr == nil {
			m = &MSPSerial{pt}
		} else {
			err = perr
		}
	}

	if err == nil {
		go m.msp_reader(c0)
		if strings.HasPrefix(name, "/dev/rfcomm") {
			time.Sleep(1500 * time.Millisecond)
		}
		log.Printf("Opened %s\n", name)
		m.MSPVariant()
		return m, nil
	}
	return nil, err
}

func (p *MSPSerial) MSPClose() {
	p.SerDev.Close()
}
