# Dokploy API Research

Last updated: 2026-04-05

This note is the working API reference for `Dokploy Radar`.

It is not a line-by-line rewrite of every Dokploy endpoint. The published OpenAPI spec currently exposes 450 operations across 40+ tags, so this document focuses on:

- the endpoints already used by `Dokploy Radar`
- the endpoints most relevant to monitoring, inspection, notifications, and safe actions
- the quirks discovered while probing a real Dokploy instance
- a tag inventory so we know what other areas exist in the spec

## Primary Sources

- API overview: https://docs.dokploy.com/docs/api
- Application reference: https://docs.dokploy.com/docs/api/reference-application
- Compose reference: https://docs.dokploy.com/docs/api/reference-compose
- Deployment reference: https://docs.dokploy.com/docs/api/reference-deployment
- Project reference: https://docs.dokploy.com/docs/api/reference-project
- Preview Deployment reference: https://docs.dokploy.com/docs/api/reference-previewDeployment
- Backup reference: https://docs.dokploy.com/docs/api/reference-backup
- Server reference: https://docs.dokploy.com/docs/api/reference-server
- Notification reference: https://docs.dokploy.com/docs/api/reference-notification
- Domain reference: https://docs.dokploy.com/docs/api/reference-domain
- Mounts reference: https://docs.dokploy.com/docs/api/reference-mounts
- Port reference: https://docs.dokploy.com/docs/api/reference-port
- Redirects reference: https://docs.dokploy.com/docs/api/reference-redirects
- Environment reference: https://docs.dokploy.com/docs/api/reference-environment
- OpenAPI spec in Dokploy repo: https://github.com/Dokploy/dokploy/blob/canary/openapi.json
- Watch Paths concept doc: https://docs.dokploy.com/docs/core/watch-paths
- Preview Deployments concept doc: https://docs.dokploy.com/docs/core/applications/preview-deployments
- Rollbacks concept doc: https://docs.dokploy.com/docs/core/applications/rollbacks
- Backups concept doc: https://docs.dokploy.com/docs/core/backups
- Volume Backups concept doc: https://docs.dokploy.com/docs/core/volume-backups
- Auto Deploy concept doc: https://docs.dokploy.com/docs/core/auto-deploy

## API Basics

Dokploy's default API base is:

```text
https://your-dokploy-host/api
```

Swagger UI is typically exposed at:

```text
https://your-dokploy-host/swagger
```

For normal API usage, Dokploy docs show `x-api-key` auth. In practice, `Dokploy Radar` also sends `Authorization: Bearer <token>` because some parts of the docs and generated schemas imply bearer-style auth for certain routes.

Minimal read example:

```bash
curl -X GET \
  'https://your-host/api/project.allForPermissions' \
  -H 'accept: application/json' \
  -H 'x-api-key: YOUR_TOKEN'
```

## What Dokploy Radar Uses Today

Current app usage in `/Sources/DokployRadar/DokployAPIClient.swift`:

- `GET /project.allForPermissions`
- fallback `GET /project.all`
- `GET /deployment.allCentralized`
- `GET /deployment.all?applicationId=...`
- `GET /deployment.allByCompose?composeId=...`
- `GET /application.one?applicationId=...`
- `GET /compose.one?composeId=...`
- `GET /compose.loadServices?composeId=...`
- `GET /compose.loadMountsByService?composeId=...&serviceName=...`
- `GET /compose.getConvertedCompose?composeId=...`

That means the app already covers:

- project/environment inventory
- application and compose inventory
- centralized deployment status
- per-service deployment history
- service inspector details for applications and compose
- compose internal service list
- per-service compose mounts
- rendered compose output

## Live Probe Findings

Observed on a real Dokploy instance while building this app:

- `project.allForPermissions` returned `5` applications and `30` compose services.
- `deployment.allCentralized` returned `281` deployment records.
- `deployment.queueList` returned `0` at the time of probing.
- `previewDeployment.all` worked, but returned `0` for the sampled application.
- `application.one` returned a large config object including:
  - `domains`
  - `ports`
  - `mounts`
  - `deployments`
  - `previewDeployments`
  - `watchPaths`
  - `sourceType`
  - `buildType`
  - provider-specific branch/repo fields
- `compose.one` returned a large config object including:
  - `composeFile`
  - `domains`
  - `mounts`
  - `deployments`
  - `backups`
  - `watchPaths`
  - `sourceType`
  - `composeType`
  - `isolatedDeployment`
- `compose.loadServices` returned internal compose service names.
- `compose.loadMountsByService` returned Docker-style mount dictionaries with keys like:
  - `Source`
  - `Destination`
  - `Type`
  - `Mode`
  - `RW`
- `compose.getConvertedCompose` returned rendered compose YAML as plain text.
- `server.all` returned `0` with the tested API token, which strongly suggests server visibility is permission-scoped.

Important implication: Dokploy has enough read-only data to build a serious monitoring app without adding unsafe admin features first.

## Core Monitoring Endpoints

### Project and Inventory

Used to build the top-level service inventory.

```text
GET /project.all
GET /project.allForPermissions
GET /project.one?projectId=...
GET /project.search?q=...
POST /project.create
POST /project.update
POST /project.duplicate
POST /project.remove
```

Notes:

- `project.allForPermissions` is the preferred inventory endpoint.
- `project.all` is a good fallback for older Dokploy versions or decoding mismatches.
- The inventory payload nests services inside `project -> environments -> applications / compose / databases`.

Example:

```bash
curl -X GET \
  'https://your-host/api/project.search?q=api' \
  -H 'accept: application/json' \
  -H 'x-api-key: YOUR_TOKEN'
```

### Deployment

Used for activity, status, history, and queue views.

```text
GET /deployment.all?applicationId=...
GET /deployment.allByCompose?composeId=...
GET /deployment.allByServer?serverId=...
GET /deployment.allByType?id=...&type=application|compose|server|schedule|previewDeployment|backup|volumeBackup
GET /deployment.allCentralized
GET /deployment.queueList
POST /deployment.killProcess
POST /deployment.removeDeployment
```

Notes:

- `deployment.allCentralized` is the best cross-service feed.
- `deployment.allByType` is broader than `all` and `allByCompose`, but the specialized endpoints are simpler for app and compose history.
- In live probing, centralized deployment objects did not reliably expose a useful top-level `serviceType`, so matching by nested `application.applicationId` / `compose.composeId` is safer.

Examples:

```bash
curl -X GET \
  'https://your-host/api/deployment.allCentralized' \
  -H 'accept: application/json' \
  -H 'x-api-key: YOUR_TOKEN'
```

```bash
curl -X GET \
  'https://your-host/api/deployment.allByType?id=YOUR_COMPOSE_ID&type=compose' \
  -H 'accept: application/json' \
  -H 'x-api-key: YOUR_TOKEN'
```

### Application

Used for detailed inspection and safe app actions.

```text
GET /application.one?applicationId=...
GET /application.search
GET /application.readAppMonitoring?appName=...
GET /application.readTraefikConfig?applicationId=...
POST /application.deploy
POST /application.redeploy
POST /application.start
POST /application.stop
POST /application.cancelDeployment
POST /application.killBuild
POST /application.cleanQueues
POST /application.clearDeployments
POST /application.markRunning
POST /application.reload
POST /application.move
POST /application.update
POST /application.saveEnvironment
POST /application.saveBuildType
POST /application.saveDockerProvider
POST /application.saveGitProvider
POST /application.saveGithubProvider
POST /application.saveGitlabProvider
POST /application.saveBitbucketProvider
POST /application.saveGiteaProvider
POST /application.refreshToken
POST /application.disconnectGitProvider
POST /application.updateTraefikConfig
POST /application.create
POST /application.delete
```

High-value fields returned by `application.one`:

- `applicationStatus`
- `sourceType`
- `buildType`
- `repository`
- `branch`
- `autoDeploy`
- `watchPaths`
- `domains`
- `ports`
- `mounts`
- `deployments`
- `previewDeployments`
- `isPreviewDeploymentsActive`
- `registry`
- `rollbackActive`
- `env`
- provider-specific repo metadata

Example reads:

```bash
curl -X GET \
  'https://your-host/api/application.one?applicationId=YOUR_APPLICATION_ID' \
  -H 'accept: application/json' \
  -H 'x-api-key: YOUR_TOKEN'
```

```bash
curl -X GET \
  'https://your-host/api/application.readTraefikConfig?applicationId=YOUR_APPLICATION_ID' \
  -H 'accept: application/json' \
  -H 'x-api-key: YOUR_TOKEN'
```

Example safe action bodies:

```bash
curl -X POST \
  'https://your-host/api/application.redeploy' \
  -H 'accept: application/json' \
  -H 'Content-Type: application/json' \
  -H 'x-api-key: YOUR_TOKEN' \
  -d '{
    "applicationId": "YOUR_APPLICATION_ID",
    "title": "Manual redeploy",
    "description": "Triggered from Dokploy Radar"
  }'
```

```bash
curl -X POST \
  'https://your-host/api/application.stop' \
  -H 'accept: application/json' \
  -H 'Content-Type: application/json' \
  -H 'x-api-key: YOUR_TOKEN' \
  -d '{"applicationId":"YOUR_APPLICATION_ID"}'
```

### Monitoring and Container Metrics

Used for runtime monitoring, especially when a compose service needs to be
resolved down to concrete containers.

```text
GET /application.readAppMonitoring?appName=...
GET /docker.getContainersByAppNameMatch?appName=...&appType=stack|docker-compose
GET /user.getMetricsToken
GET /user.getContainerMetrics?url=...&token=...&appName=...&dataPoints=...
WS  /listen-docker-stats-monitoring?appName=...&appType=application|stack|docker-compose
POST /server.setupMonitoring
POST /admin.setupMonitoring
POST /settings.cleanMonitoring
```

Notes:

- `application.readAppMonitoring` is the only published container-metrics route
  in the application router.
- There is no published `compose.readAppMonitoring` endpoint in Dokploy's
  OpenAPI spec.
- `docker.getContainersByAppNameMatch` is the bridge for compose monitoring.
  It resolves a compose service to one or more container names.
- Dokploy's own compose monitoring UI is container-centric:
  1. resolve containers with `docker.getContainersByAppNameMatch`
  2. select a concrete container name
  3. fetch historical stats for that container name
  4. open a live websocket stream for that container name
- The websocket route `/listen-docker-stats-monitoring` is used by Dokploy's
  web UI for live updates, but it authenticates with the browser session rather
  than `x-api-key`.
- In live probing against the tested instance:
  - `docker.getContainersByAppNameMatch` worked with `x-api-key`
  - `application.readAppMonitoring` returned `null` for sampled compose
    container names
  - `user.getMetricsToken` worked with `x-api-key`
  - `user.getContainerMetrics` is present in the spec, but the tested instance
    returned `enabledFeatures: false` and an empty metrics token, so the paid
    monitoring path was not usable there

Implication:

- Compose monitoring exists in Dokploy's product, but there is no clean,
  compose-specific public API route equivalent to
  `application.readAppMonitoring`.
- For third-party clients like `Dokploy Radar`, compose monitoring should be
  treated as conditional:
  - historical data may be absent
  - the free live-monitoring path depends on a browser-session websocket
  - paid/external monitoring may be available via `user.getMetricsToken` and
    `user.getContainerMetrics`

Examples:

```bash
curl -X GET \
  'https://your-host/api/docker.getContainersByAppNameMatch?appName=YOUR_COMPOSE_APP_NAME&appType=stack' \
  -H 'accept: application/json' \
  -H 'x-api-key: YOUR_TOKEN'
```

```bash
curl -X GET \
  'https://your-host/api/application.readAppMonitoring?appName=YOUR_CONTAINER_NAME' \
  -H 'accept: application/json' \
  -H 'x-api-key: YOUR_TOKEN'
```

```bash
curl -X GET \
  'https://your-host/api/user.getMetricsToken' \
  -H 'accept: application/json' \
  -H 'x-api-key: YOUR_TOKEN'
```

```bash
curl -X GET \
  'https://your-host/api/user.getContainerMetrics?url=MONITORING_BASE_URL&token=MONITORING_TOKEN&appName=YOUR_CONTAINER_NAME&dataPoints=50' \
  -H 'accept: application/json' \
  -H 'x-api-key: YOUR_TOKEN'
```

### Compose

Used for compose-first monitoring and safe compose actions.

```text
GET /compose.one?composeId=...
GET /compose.search
GET /compose.loadServices?composeId=...
GET /compose.loadMountsByService?composeId=...&serviceName=...
GET /compose.getConvertedCompose?composeId=...
GET /compose.getDefaultCommand
GET /compose.getTags
GET /compose.templates
POST /compose.deploy
POST /compose.redeploy
POST /compose.start
POST /compose.stop
POST /compose.cancelDeployment
POST /compose.killBuild
POST /compose.cleanQueues
POST /compose.clearDeployments
POST /compose.randomizeCompose
POST /compose.isolatedDeployment
POST /compose.fetchSourceType
POST /compose.processTemplate
POST /compose.import
POST /compose.move
POST /compose.update
POST /compose.refreshToken
POST /compose.disconnectGitProvider
POST /compose.create
POST /compose.delete
POST /compose.deployTemplate
```

High-value fields returned by `compose.one`:

- `composeStatus`
- `sourceType`
- `composeType`
- `repository`
- `branch`
- `autoDeploy`
- `watchPaths`
- `domains`
- `mounts`
- `deployments`
- `backups`
- `composeFile`
- `isolatedDeployment`
- `randomize`
- `env`

Example reads:

```bash
curl -X GET \
  'https://your-host/api/compose.one?composeId=YOUR_COMPOSE_ID' \
  -H 'accept: application/json' \
  -H 'x-api-key: YOUR_TOKEN'
```

```bash
curl -X GET \
  'https://your-host/api/compose.loadServices?composeId=YOUR_COMPOSE_ID' \
  -H 'accept: application/json' \
  -H 'x-api-key: YOUR_TOKEN'
```

```bash
curl -X GET \
  'https://your-host/api/compose.loadMountsByService?composeId=YOUR_COMPOSE_ID&serviceName=web' \
  -H 'accept: application/json' \
  -H 'x-api-key: YOUR_TOKEN'
```

```bash
curl -X GET \
  'https://your-host/api/compose.getConvertedCompose?composeId=YOUR_COMPOSE_ID' \
  -H 'accept: application/json' \
  -H 'x-api-key: YOUR_TOKEN'
```

Example safe action body:

```bash
curl -X POST \
  'https://your-host/api/compose.redeploy' \
  -H 'accept: application/json' \
  -H 'Content-Type: application/json' \
  -H 'x-api-key: YOUR_TOKEN' \
  -d '{
    "composeId": "YOUR_COMPOSE_ID",
    "title": "Manual redeploy",
    "description": "Triggered from Dokploy Radar"
  }'
```

### Preview Deployment

Good for PR environment monitoring.

```text
GET /previewDeployment.all?applicationId=...
GET /previewDeployment.one?previewDeploymentId=...
POST /previewDeployment.redeploy
POST /previewDeployment.delete
```

Example:

```bash
curl -X GET \
  'https://your-host/api/previewDeployment.all?applicationId=YOUR_APPLICATION_ID' \
  -H 'accept: application/json' \
  -H 'x-api-key: YOUR_TOKEN'
```

```bash
curl -X POST \
  'https://your-host/api/previewDeployment.redeploy' \
  -H 'accept: application/json' \
  -H 'Content-Type: application/json' \
  -H 'x-api-key: YOUR_TOKEN' \
  -d '{
    "previewDeploymentId": "YOUR_PREVIEW_DEPLOYMENT_ID",
    "title": "Manual preview rebuild",
    "description": "Triggered from Dokploy Radar"
  }'
```

### Domain, Mount, Port, Redirect, Rollback

These are useful for richer inspectors and later management views.

```text
GET /domain.byApplicationId?applicationId=...
GET /domain.byComposeId?composeId=...
GET /domain.one?domainId=...
POST /domain.create
POST /domain.update
POST /domain.delete
POST /domain.generateDomain
POST /domain.validateDomain
GET /domain.canGenerateTraefikMeDomains
```

```text
GET /mounts.allNamedByApplicationId?applicationId=...
GET /mounts.listByServiceId?serviceId=...
GET /mounts.one?mountId=...
POST /mounts.create
POST /mounts.update
POST /mounts.remove
```

```text
GET /port.one?portId=...
POST /port.create
POST /port.update
POST /port.delete
```

```text
GET /redirects.one?redirectId=...
POST /redirects.create
POST /redirects.update
POST /redirects.delete
```

```text
POST /rollback.rollback
POST /rollback.delete
```

Example rollback body:

```bash
curl -X POST \
  'https://your-host/api/rollback.rollback' \
  -H 'accept: application/json' \
  -H 'Content-Type: application/json' \
  -H 'x-api-key: YOUR_TOKEN' \
  -d '{"rollbackId":"YOUR_ROLLBACK_ID"}'
```

### Backup

These are strong later features, but not first-priority for the app.

```text
GET /backup.one?backupId=...
GET /backup.listBackupFiles?destinationId=...&search=...
POST /backup.create
POST /backup.update
POST /backup.remove
POST /backup.manualBackupCompose
POST /backup.manualBackupMariadb
POST /backup.manualBackupMongo
POST /backup.manualBackupMySql
POST /backup.manualBackupPostgres
POST /backup.manualBackupWebServer
```

Examples:

```bash
curl -X GET \
  'https://your-host/api/backup.listBackupFiles?destinationId=DEST_ID&search=' \
  -H 'accept: application/json' \
  -H 'x-api-key: YOUR_TOKEN'
```

```bash
curl -X POST \
  'https://your-host/api/backup.manualBackupCompose' \
  -H 'accept: application/json' \
  -H 'Content-Type: application/json' \
  -H 'x-api-key: YOUR_TOKEN' \
  -d '{"backupId":"YOUR_BACKUP_ID"}'
```

### Server

Interesting, but likely permission-scoped and not the best immediate product priority.

```text
GET /server.all
GET /server.one?serverId=...
GET /server.count
GET /server.buildServers
GET /server.publicIp
GET /server.getDefaultCommand
GET /server.getServerTime
GET /server.validate?serverId=...
GET /server.security?serverId=...
GET /server.getServerMetrics?url=...&token=...&dataPoints=...
GET /server.withSSHKey
POST /server.create
POST /server.update
POST /server.remove
POST /server.setup
POST /server.setupMonitoring
```

Important quirk:

- `server.getServerMetrics` takes `url`, `token`, and `dataPoints` according to the spec, not `serverId`.
- `server.all` returned `0` with the tested token, so token scope matters.

## Nearby Feature Areas Exposed by the Spec

These are not core to `Dokploy Radar` yet, but they are present:

- `notification` (`38` endpoints)
- `settings` (`49` endpoints)
- `user`, `organization`, `sso`
- `destination`, `registry`, `sshKey`
- database families:
  - `postgres`
  - `mysql`
  - `mariadb`
  - `mongo`
  - `redis`
- `volumeBackups`
- `security`
- `schedule`
- `swarm`
- `cluster`
- git provider integrations:
  - `github`
  - `gitlab`
  - `bitbucket`
  - `gitea`

For our app, these are mostly "maybe later" unless we decide to build broader Dokploy admin tooling.

## OpenAPI Tag Inventory

Tag counts from the published Dokploy OpenAPI spec on 2026-04-05:

```text
admin: 1
ai: 9
application: 29
backup: 11
bitbucket: 7
certificates: 4
cluster: 4
compose: 28
deployment: 8
destination: 6
docker: 7
domain: 9
environment: 7
gitProvider: 2
gitea: 8
github: 6
gitlab: 7
licenseKey: 6
mariadb: 14
mongo: 14
mounts: 6
mysql: 14
notification: 38
organization: 10
patch: 12
port: 4
postgres: 14
previewDeployment: 4
project: 8
redirects: 4
redis: 14
registry: 7
rollback: 2
schedule: 6
security: 4
server: 16
settings: 49
sshKey: 6
sso: 10
stripe: 7
swarm: 3
untagged: 1
user: 18
volumeBackups: 6
```

## Quirks and Integration Notes

Things to remember when building against Dokploy:

- Prefer `x-api-key` auth for normal API calls.
- Keep a tolerant decoder strategy. Many endpoints return very large objects and the docs do not always describe every field in a stable, strongly typed way.
- Do not assume every token can see everything.
  - `server.all` returned no visible servers with the tested token.
- Preserve base-path Dokploy installs.
  - `https://example.com/dokploy` must become `https://example.com/dokploy/api/...`, not `https://example.com/api/...`.
- `deployment.allCentralized` is excellent for a global activity feed, but not ideal as the only source of truth for detailed service type semantics.
- `compose.getConvertedCompose` returns raw text, not structured JSON.
- `compose.loadMountsByService` returns Docker-style keys like `Source` and `Destination`, so parsing should be case-tolerant.
- `application.readAppMonitoring` takes `appName`, not `applicationId`.
- Compose monitoring is not exposed as a published `compose.*` monitoring route.
  Dokploy's own compose UI resolves container names first, then uses generic
  monitoring paths.
- The free live-monitoring websocket uses browser-session auth, not `x-api-key`.
  That makes it unsuitable as a stable public integration surface for a desktop
  client.
- `docker.getContainersByAppNameMatch`, `user.getMetricsToken`, and
  `user.getContainerMetrics` are the most relevant monitoring-adjacent routes
  for compose services.
- `server.getServerMetrics` uses `url` + `token` + `dataPoints` per the published spec.

## Recommended Product Directions Based on the API

Best next read-only features:

1. Unified cross-instance activity feed
2. Compose-first deep monitoring
3. Preview deployment monitoring
4. Configuration audit / risk badges
5. Richer deployment timelines with commit metadata

Best later action features:

1. Application and compose redeploy/start/stop
2. Cancel deployment / kill build
3. Preview redeploy/delete
4. Rollback entry points

Not first-priority:

- server management
- notification-provider management
- broad settings/admin UIs
- destination/registry CRUD
- full project/environment editing

## If We Need to Go Deeper Later

Good next additions to this note:

- request/response examples for database family endpoints
- deeper server metrics research once we have a token with server visibility
- notification-provider payload examples
- backup and volume-backup payload examples
- diff between Dokploy release versions if we hit API drift
