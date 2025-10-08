#!/usr/bin/env python3
import argparse
import concurrent.futures
import time
import requests


def hit(url: str, timeout: float):
    try:
        r = requests.get(url, timeout=timeout)
        return r.status_code
    except Exception:
        return None


def main():
    p = argparse.ArgumentParser(description="Simple HTTP load tester")
    p.add_argument("--url", default="http://localhost:8080/healthz", help="Target URL")
    p.add_argument("--concurrency", type=int, default=50, help="Concurrent workers")
    p.add_argument("--duration", type=int, default=60, help="Duration in seconds")
    p.add_argument("--timeout", type=float, default=2.0, help="Request timeout")
    args = p.parse_args()

    print(f"Load test -> {args.url}  for {args.duration}s  with {args.concurrency} workers")
    end = time.time() + args.duration
    ok = 0
    fail = 0
    total = 0

    with concurrent.futures.ThreadPoolExecutor(max_workers=args.concurrency) as ex:
        while time.time() < end:
            futs = [ex.submit(hit, args.url, args.timeout) for _ in range(args.concurrency)]
            for f in concurrent.futures.as_completed(futs):
                code = f.result()
                total += 1
                if code == 200:
                    ok += 1
                else:
                    fail += 1
    print(f"Done. total={total} ok={ok} fail={fail}")


if __name__ == "__main__":
    main()
