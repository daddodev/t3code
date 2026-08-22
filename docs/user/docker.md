# Run T3 Code in a container

The container runs the T3 Code server and its bundled web client on port 3773. The published image
includes GitHub CLI (`gh`), Codex (`codex`), Claude Code (`claude`), and OpenCode (`opencode`).
Provider credentials are still kept outside the image and should be mounted as persistent writable
volumes because the CLIs also store local state alongside their credentials.

Codex stores MCP OAuth credentials in its mounted config directory rather than an ephemeral desktop
keyring. To make an existing host login available in the container, authenticate once using the
same file-backed store:

```bash
codex -c 'mcp_oauth_credentials_store="file"' mcp login figma
```

The resulting credentials remain available to `codex` inside recreated containers as long as the
Codex config directory is mounted read-write.

## Docker Compose

Start T3 Code against the current directory:

```bash
docker compose up --build
```

Copy the one-time pairing URL printed by `docker compose logs t3code` into a browser, replacing
the container IP in it with `localhost:3773`. State, pairing credentials, and logs persist in the
`t3-data` volume. Set
`T3CODE_WORKSPACE=/absolute/path/to/project` before starting Compose to use another workspace.

To use a published image instead of building locally:

```bash
T3CODE_IMAGE=ghcr.io/pingdotgg/t3code:latest docker compose up
```

The GitHub Actions workflow publishes images to GitHub Container Registry for pushes to `main` and
version tags. Change the image name in `docker-compose.yml` if you publish a fork.

## Kubernetes

The manifests create one stateful server, a persistent data volume, and a persistent workspace
volume:

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/t3code.yaml
```

Before applying `k8s/ingress.yaml`, replace `t3code.example.com` and `ingressClassName` with values
for your cluster. The ingress must support WebSocket upgrades. For a local check without ingress:

```bash
kubectl -n t3code port-forward service/t3code 3773:3773
```

Then use the pairing URL from `kubectl -n t3code logs statefulset/t3code`, replacing its pod IP
with `localhost:3773`. With an ingress, replace the pod IP with the ingress hostname instead.

Mount provider credentials through your cluster's secret mechanism. Cursor, Grok, and GitLab CLI are
not included because their installation and authentication are environment-specific; add them in a
derived image when needed. Treat the data volume and provider credentials as sensitive: they grant
access to agent sessions and their workspaces.
