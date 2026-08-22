# Running it on Kubernetes

The single-machine path is [`docker.md`](docker.md). This page is the Helm
chart: how the model gets onto a node, and which settings will bite you.

There is a Helm chart under `charts/southbyte-music`, using the same two images.

```bash
# From the published chart — resolves to the newest release
helm install musik oci://ghcr.io/mvdb/charts/southbyte-music \
  --namespace musik --create-namespace

# Pin a version
helm install musik oci://ghcr.io/mvdb/charts/southbyte-music --version 0.1.6 \
  --namespace musik --create-namespace

# Or from a checkout
helm install musik charts/southbyte-music \
  --namespace musik --create-namespace
```

Every push to `main` also publishes a SemVer *pre-release* (`0.1.6-main.52`).
Helm ignores those unless you pass `--devel` or name one with `--version`, so
plain `helm install` always lands on a tagged release and never on whatever was
merged last.

A released chart pins its images to that release's version tag, so a given chart
version always deploys exactly those images and cannot drift onto a newer build.
A checkout instead uses whatever `Chart.yaml` says, which on `main` is the moving
`main` tag.

The first start takes a while — the model has to reach the volume first, see
below — and the chart's `NOTES.txt` tells you which log to watch.

## The model is not in the image

It is 54 GB. An image that size is not something a cluster pulls onto a node in
any reasonable time, and every rebuild would carry it again. In Kubernetes the
model is *data*, not code: it lives in a PersistentVolume, and an initContainer
fills it.

That initContainer is idempotent in two stages. If the completion marker is
present, nothing happens at all — no network traffic, and the pod starts in
seconds. That is the normal case for every restart, rescale and node change. If
the marker is missing, `hf download` fetches what is not there; that step is
itself resumable, so an interrupted download continues rather than restarting.

The marker is written last, on purpose. If the download breaks off, it is
absent, and the next start picks up the thread instead of treating half a model
as complete.

The initContainer also normalises the backbone config (`model_type` from
`mixtral` to `qwen3`). SGLang-Omni would otherwise attempt that itself at
startup and fail against a read-only mount. Doing it here means the server can
mount the volume read-only, which it does.

## Things that will bite you if you change them

**`terminationGracePeriodSeconds: 1800`.** Five minutes of music is around 27
minutes of computation. The Kubernetes default of 30 s would cut off every
generation in progress on any rollout, restart or node drain.

**The liveness probe is the most dangerous setting in the chart.** `/health`
does answer while a generation is running — verified; it reports the number of
in-flight requests. If that were not the case, this probe would kill every long
piece it was asked to produce. The thresholds are deliberately generous anyway.

**The startup probe allows 600 s.** The server is ready after about 160 s
measured. Without a startup probe, the liveness probe would have to tolerate
that same delay and could then not detect a genuinely hung process for minutes.

**`strategy: Recreate`, not RollingUpdate.** With `ReadWriteOnce` the model
volume binds to one pod; a second would sit in Pending forever. And even with
`ReadWriteMany`, a second pod means a second GPU.

**The PVC survives `helm uninstall`** (`helm.sh/resource-policy: keep`). Those
54 GB would otherwise have to be fetched again. Delete it by hand if you mean it.

## One origin, not two

nginx proxies `/v1/` through to the model server, so the browser only ever talks
to one address. That is why `webui.endpunkt` defaults to `"/"` — same origin as
the page. No second port to expose, no CORS, one Ingress instead of two.

If you put an Ingress in front of it, raise its timeouts too. The nginx defaults
of 60 s would return a 504 on any longer piece while the server is still happily
working:

```yaml
ingress:
  annotations:
    nginx.ingress.kubernetes.io/proxy-read-timeout: "2400"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "2400"
```

## Where the images come from

The chart uses the same two images as the Docker path — how they are built and
published, and how to verify one on real hardware, is in
[`docker.md`](docker.md).

## Security posture

Non-root (uid 1000), `allowPrivilegeEscalation: false`, all capabilities
dropped, `seccompProfile: RuntimeDefault`, no API token mounted. The web UI runs
with `readOnlyRootFilesystem: true`; the model server does not, and that is an
honest `false` rather than an aspirational `true` — Torch and Triton compile
kernels at runtime and need writable paths. Those caches live in emptyDir
volumes so nothing persists into an image layer.

An optional NetworkPolicy (`networkPolicy.enabled=true`) restricts the model
server to traffic from the web UI. It is off by default because without a CNI
that enforces policies it does nothing but suggest safety that is not there.

None of this adds authentication. See *What is deliberately missing*.
