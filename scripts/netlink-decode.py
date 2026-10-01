#!/usr/bin/env python3
"""Turn a netlink pcap into a readable rtnetlink timeline.

Capture one with a netlink monitor interface, for example inside a guest:

    ip link add nlmon0 type nlmon && ip link set nlmon0 up
    tcpdump -i nlmon0 -w /tmp/nl.pcap -s 0 -U &
    ... trigger the action, then stop tcpdump ...
    scp -P 2222 root@127.0.0.1:/tmp/nl.pcap .
    python3 scripts/netlink-decode.py nl.pcap

Every NEWLINK / DELLINK / SETLINK and every error is printed with the
interesting attributes: interface name, master, peer link, netns id, address,
oper state. This shows what actually happened on the wire, including the
messages strace cannot decode and the re-registration the kernel performs when
a device changes network namespace.

Pass a second argument to filter for messages whose attributes mention that
string (for example a veth name).
"""
import struct
import sys

IFLA = {
    1: "ADDRESS", 2: "BROADCAST", 3: "IFNAME", 4: "MTU", 5: "LINK", 6: "QDISC",
    10: "MASTER", 16: "OPERSTATE", 19: "NET_NS_PID", 28: "NET_NS_FD",
    33: "CARRIER", 37: "LINK_NETNSID", 45: "NEW_NETNSID", 46: "IF_NETNSID",
}
MTYPE = {
    1: "NOOP", 2: "ERROR", 3: "DONE", 16: "NEWLINK", 17: "DELLINK",
    18: "GETLINK", 19: "SETLINK", 20: "NEWADDR", 21: "DELADDR",
    22: "GETADDR", 24: "NEWROUTE", 25: "DELROUTE", 26: "GETROUTE",
}
NUM_ATTRS = {"MASTER", "LINK", "LINK_NETNSID", "NEW_NETNSID", "IF_NETNSID",
             "NET_NS_FD", "NET_NS_PID", "MTU", "GROUP"}
SIGNED_ATTRS = {"LINK", "LINK_NETNSID"}


def decode_attrs(payload):
    out = []
    off = 0
    while off + 4 <= len(payload):
        alen, atype = struct.unpack_from("<HH", payload, off)
        if alen < 4 or off + alen > len(payload):
            break
        next_off = off + ((alen + 3) & ~3)
        aval = payload[off + 4:off + alen]
        name = IFLA.get(atype, f"attr{atype}")
        if name == "IFNAME":
            out.append(f"IFNAME={aval.split(bytes([0]))[0].decode('utf-8', 'replace')}")
        elif name in NUM_ATTRS:
            out.append(f"{name}={int.from_bytes(aval[:4], 'little', signed=name in SIGNED_ATTRS)}")
        elif name == "ADDRESS":
            out.append(f"ADDRESS={aval.hex(':')}")
        elif name in ("OPERSTATE", "CARRIER"):
            out.append(f"{name}={int.from_bytes(aval[:1], 'little')}")
        off = next_off
    return out


def main(path, name_filter=None):
    raw = open(path, "rb").read()
    if raw[:4] in (b"\xd4\xc3\xb2\xa1", b"\x4d\x3c\xb2\xa1", b"\xa1\xb2\xc3\xd4"):
        endian = "<" if raw[:4] in (b"\xd4\xc3\xb2\xa1", b"\x4d\x3c\xb2\xa1") else ">"
    else:
        sys.exit(f"{path}: not a pcap file")
    off = 24  # pcap global header
    first = None
    while off + 16 <= len(raw):
        ts_sec, ts_usec, incl, _orig = struct.unpack(endian + "IIII", raw[off:off + 16])
        data = raw[off + 16:off + 16 + incl]
        off += 16 + incl
        if first is None:
            first = ts_sec + ts_usec / 1e6
        t = ts_sec + ts_usec / 1e6 - first

        start = None
        for candidate in range(0, min(32, len(data))):
            if candidate + 6 > len(data):
                break
            mlen, mtype = struct.unpack_from("<IH", data, candidate)
            if 16 <= mlen <= len(data) - candidate and mtype in MTYPE:
                start = candidate
                break
        if start is None:
            continue

        pos = start
        while pos + 16 <= len(data):
            mlen, mtype = struct.unpack_from("<IH", data, pos)
            if mlen < 16 or pos + mlen > len(data):
                break
            body = data[pos + 16:pos + mlen]
            tname = MTYPE.get(mtype, str(mtype))
            if mtype == 2 and len(body) >= 6:  # NLMSG_ERROR
                err = struct.unpack_from("<i", body, 0)[0]
                if err != 0:
                    otype = struct.unpack_from("<H", body, 4)[0]
                    print(f"{t:9.3f} ERROR code={err} on {MTYPE.get(otype, otype)}")
            elif mtype in (16, 17, 19) and len(body) >= 16:  # NEWLINK / DELLINK / SETLINK
                _fam, _pad, _devtype, index, dflags, dchange = struct.unpack_from("<BBHiII", body, 0)
                attrs = decode_attrs(body[16:])
                if name_filter and name_filter not in " ".join(attrs):
                    pos += (mlen + 3) & ~3
                    continue
                print(f"{t:9.3f} {tname:8s} idx={index:<4d} "
                      f"flags=0x{dflags:08x} change=0x{dchange:08x} {' '.join(attrs)}")
            pos += (mlen + 3) & ~3


if __name__ == "__main__":
    if len(sys.argv) not in (2, 3):
        sys.exit("usage: netlink-decode.py <pcap> [attribute-substring]")
    try:
        import signal

        signal.signal(signal.SIGPIPE, signal.SIG_DFL)  # e.g. piping into head
    except (ImportError, AttributeError):
        pass
    main(sys.argv[1], sys.argv[2] if len(sys.argv) == 3 else None)
