# RUNBOOK : kubectl "no route to host"

## Trigger

`kubectl` fails with `dial tcp x.x.x.x:xxxx: no route to host`

## Root cause

minikube not running, VPN active.

## Checklist

**minikube working?**

```bash
minikube status
```

**Stopped / Paused?**

```bash
minikube start
```

**Running?**

> Move on

**Is the IP address correct and visible?**

```bash
minikube ip
ping -c 3 $(minikube ip)
```

**No response?**

> check VPN / reboot the network

```bash
minikube stop && start
```

**Ping OK?**

> Move on

**Does `kubeconfig` have the right IP?**

```bash
kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}'
```

**IP is different?**

```bash
minikube update-context
```

**IP = the same as with minikube ip?**

> Move on

**_Does the `kubectl` respond?_**

```bash
kubectl get nodes
```

**Shows Ready?**

> ✅ fixed

**Next error?**

```bash
minikube delete && minikube start
```
