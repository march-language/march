`[P4]` Udp: an opt-in AF_XDP (kernel-bypass) backend

For rates beyond what the kernel stack gives (`recvmmsg` + GRO measured ~3.4M
pps at 1200 B on loopback), AF_XDP offers zero-copy NIC rings while the kernel
keeps the device. It needs CAP_NET_ADMIN/CAP_BPF, driver support, an XDP
program to steer the flow and a UMEM, so it must be opt-in (a separate
`Udp.open_xdp(iface, queue, ...)` or package), never the default. DPDK/netmap
were considered and rejected for the stdlib: they take the NIC from the kernel,
need hugepages and a dedicated busy-polling core, and require bringing an
IP/ARP stack. Prerequisite: the io_uring backend todo, which covers most users
without privileges.
