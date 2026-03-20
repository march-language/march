#!/bin/bash
# HTTP GET benchmark - curl sequential
N=20
URL="http://httpbin.org/get"
echo "curl HTTP GET benchmark: $N sequential requests to $URL"
start=$(python3 -c 'import time; print(time.monotonic())')
for i in $(seq 1 $N); do
  curl -s -o /dev/null "$URL"
done
end=$(python3 -c 'import time; print(time.monotonic())')
elapsed=$(python3 -c "print(f'{$end - $start:.3f}')")
per_req=$(python3 -c "print(f'{($end - $start) / $N * 1000:.1f}')")
echo "done in ${elapsed}s (${per_req}ms/req)"
