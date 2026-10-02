#!/usr/bin/env python3
"""
ICMP-Ghost LLDP Output Parser
Parses the hex output of the !L (network map) command.

Usage:
    # Paste hex output directly:
    echo "01 80 c2 00 00 0e 22 e1 5d..." | python3 lldp_parse.py

    # Or pipe client output:
    sudo ./client | python3 lldp_parse.py

Author : JM00NJ | netacoding.com
License: AGPL-3.0
"""

import sys
import struct
import re

# LLDP TLV type names
TLV_TYPES = {
    0: "End",
    1: "Chassis ID",
    2: "Port ID",
    3: "TTL",
    4: "Port Description",
    5: "System Name",
    6: "System Description",
    7: "System Capabilities",
    8: "Management Address",
}

CHASSIS_SUBTYPES = {
    1: "Chassis Component",
    2: "Interface Alias",
    3: "Port Component",
    4: "MAC Address",
    5: "Network Address",
    6: "Interface Name",
    7: "Locally Assigned",
}

PORT_SUBTYPES = {
    1: "Interface Alias",
    2: "Port Component",
    3: "MAC Address",
    4: "Network Address",
    5: "Interface Name",
    6: "Agent Circuit ID",
    7: "Locally Assigned",
}


def format_mac(b):
    return ':'.join(f'{x:02x}' for x in b)


def parse_lldp_frame(frame: bytes, frame_no: int):
    if len(frame) < 14:
        return

    dst_mac = format_mac(frame[0:6])
    src_mac = format_mac(frame[6:12])
    etype   = struct.unpack('>H', frame[12:14])[0]

    print(f"\n┌─[ Frame {frame_no} ]{'─' * 40}")
    print(f"│  SRC MAC   : {src_mac}")
    print(f"│  DST MAC   : {dst_mac}")
    print(f"│  EtherType : 0x{etype:04x} ({'LLDP ✓' if etype == 0x88CC else 'unknown'})")

    if etype != 0x88CC:
        print("└" + "─" * 50)
        return

    tlv_data = frame[14:]
    k = 0
    while k + 2 <= len(tlv_data):
        hdr = struct.unpack('>H', tlv_data[k:k+2])[0]
        tlv_type = (hdr >> 9) & 0x7F
        tlv_len  = hdr & 0x1FF

        if tlv_type == 0:
            break

        if k + 2 + tlv_len > len(tlv_data):
            break

        val = tlv_data[k+2 : k+2+tlv_len]
        type_name = TLV_TYPES.get(tlv_type, f"Type {tlv_type}")

        if tlv_type == 1 and len(val) >= 1:
            subtype = val[0]
            subname = CHASSIS_SUBTYPES.get(subtype, f"subtype={subtype}")
            if subtype == 4 and len(val) == 7:
                print(f"│  Chassis ID: {format_mac(val[1:])} ({subname})")
            else:
                print(f"│  Chassis ID: {val[1:].hex()} ({subname})")

        elif tlv_type == 2 and len(val) >= 1:
            subtype = val[0]
            subname = PORT_SUBTYPES.get(subtype, f"subtype={subtype}")
            if subtype == 3 and len(val) == 7:
                print(f"│  Port ID   : {format_mac(val[1:])} ({subname})")
            elif subtype == 5:
                print(f"│  Port ID   : {val[1:].decode('utf-8','ignore')} ({subname})")
            else:
                print(f"│  Port ID   : {val[1:].hex()} ({subname})")

        elif tlv_type == 3 and len(val) == 2:
            ttl = struct.unpack('>H', val)[0]
            print(f"│  TTL       : {ttl}s")

        elif tlv_type == 4:
            print(f"│  Port Desc : {val.decode('utf-8','ignore')}")

        elif tlv_type == 5:
            print(f"│  Sys Name  : {val.decode('utf-8','ignore')}")

        elif tlv_type == 6:
            print(f"│  Sys Desc  : {val.decode('utf-8','ignore').strip()[:60]}")

        else:
            print(f"│  {type_name:<12}: {val.hex()}")

        k += 2 + tlv_len

    print("└" + "─" * 50)


def extract_hex_from_input(text: str) -> bytes:
    """Extract hex bytes from !L output — handles spaces and newlines."""
    # Find all hex byte patterns (xx format)
    tokens = re.findall(r'\b[0-9a-fA-F]{2}\b', text)
    return bytes(int(t, 16) for t in tokens)


def main():
    # Read all input (stdin or piped)
    raw = sys.stdin.read()

    # Filter to only lines that look like hex dump
    # (skip C2 console lines like "[+] Sending Command...")
    hex_lines = []
    for line in raw.splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        # Keep lines that are mostly hex bytes
        tokens = stripped.split()
        hex_count = sum(1 for t in tokens if re.match(r'^[0-9a-fA-F]{2}$', t))
        if len(tokens) > 0 and hex_count / len(tokens) > 0.7:
            hex_lines.append(stripped)

    if not hex_lines:
        print("[!] No hex data found in input.")
        print("    Usage: sudo ./client | python3 lldp_parse.py")
        print("    Or:    echo '01 80 c2 ...' | python3 lldp_parse.py")
        sys.exit(1)

    data = extract_hex_from_input(' '.join(hex_lines))
    total = len(data)
    frame_size = 60
    frame_count = total // frame_size

    print(f"ICMP-Ghost LLDP Parser — {total} bytes → {frame_count} frame(s)")
    print("=" * 52)

    seen = set()
    unique = 0

    for i in range(frame_count):
        frame = data[i * frame_size : (i+1) * frame_size]
        # Deduplicate identical frames
        key = frame[6:12]  # SRC MAC as dedup key
        if key not in seen:
            seen.add(key)
            unique += 1
            parse_lldp_frame(frame, unique)

    if frame_count > unique:
        print(f"\n[i] {frame_count - unique} duplicate frame(s) suppressed.")

    print(f"\n[+] Found {unique} unique neighbor(s).")


if __name__ == "__main__":
    main()
