/* march_udp.h — UDP datagram builtins (march_udp.c, stdlib/udp.march). */
#pragma once
#include <stdint.h>

void *march_udp_open(void *host, int64_t port, int64_t opts, int64_t rcvbuf, int64_t sndbuf);
void *march_udp_resolve(void *host, int64_t port);
void *march_udp_addr_to_string(void *addr);
void *march_udp_connect(int64_t fd, void *addr);
void  march_udp_close(int64_t fd);
void *march_udp_local_addr(int64_t fd);
void *march_udp_stats(int64_t fd);
void *march_udp_send_batch(int64_t fd, void *addr, void *payloads);
void *march_udp_send_many(int64_t fd, void *pairs);
void *march_udp_recv_batch(int64_t fd, int64_t max_msgs, int64_t max_size, int64_t timeout_ms);
