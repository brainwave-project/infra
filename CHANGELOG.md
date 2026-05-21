## [1.2.2](https://github.com/brainwave-project/infra/compare/v1.2.1...v1.2.2) (2026-05-21)


### Bug Fixes

* **infra:** replace Konga with Kong Manager, fix smart-quote corruption ([124bd57](https://github.com/brainwave-project/infra/commit/124bd578be8e349b3be1deb0fa3be47c6ec0d3e4))

## [1.2.1](https://github.com/brainwave-project/infra/compare/v1.2.0...v1.2.1) (2026-05-16)

# [1.2.0](https://github.com/brainwave-project/infra/compare/v1.1.3...v1.2.0) (2026-05-16)


### Features

* **observability:** wire OTel auto-instrumentation into all dev service containers ([d7298f5](https://github.com/brainwave-project/infra/commit/d7298f5ae6d4c3b9418bcb07e09d4eff008cfd39))

## [1.1.3](https://github.com/brainwave-project/infra/compare/v1.1.2...v1.1.3) (2026-05-16)


### Bug Fixes

* **audit-hub:** remove prisma db push from dev startup command ([1e3fcb2](https://github.com/brainwave-project/infra/commit/1e3fcb24d1a6b2cb2590bf20bca987aa6d078473))

## [1.1.2](https://github.com/brainwave-project/infra/compare/v1.1.1...v1.1.2) (2026-05-15)


### Bug Fixes

* **observability:** unblock loki + tempo crash loops ([a4f4b3f](https://github.com/brainwave-project/infra/commit/a4f4b3f5fe309014b894bf3efc19f77181e9435e))

## [1.1.1](https://github.com/brainwave-project/infra/compare/v1.1.0...v1.1.1) (2026-05-15)


### Bug Fixes

* **otel:** remap zPages host port 55679 → 5679 to dodge Windows reservation ([a2bbca4](https://github.com/brainwave-project/infra/commit/a2bbca4ae0db02cfa3ea84593966c8d3d7fbe4c0))

# [1.1.0](https://github.com/brainwave-project/infra/compare/v1.0.0...v1.1.0) (2026-05-15)


### Bug Fixes

* **ci:** anchor semantic-release with v1.0.0 tag + clean duplicated CHANGELOG ([abe0ff4](https://github.com/brainwave-project/infra/commit/abe0ff44014dc7d65270b33602cdf20eb3a82325))
* **ci:** drop redundant `git fetch --tags --force` step in release workflow ([45eca19](https://github.com/brainwave-project/infra/commit/45eca19b9167e99422a51dd1add2c1a5e0d4f895))
* **ci:** force-fetch tags before semantic-release to avoid orphan-tag conflicts ([76ede03](https://github.com/brainwave-project/infra/commit/76ede037d8dc2d1e15f4cda9dd2b976a33e42b05))
* **ci:** kong lint + secrets scan ([4be9306](https://github.com/brainwave-project/infra/commit/4be930628e4c1c564fb8af32bc1e9e57426260c9))


### Features

* **infra:** add audit-hub to compose.prod.yml + .env.prod.example ([08a478f](https://github.com/brainwave-project/infra/commit/08a478f780cf79fcb46e47a6e78498124d9a4c8c))
* **infra:** add Kafka infrastructure and audit-hub routing ([4e63662](https://github.com/brainwave-project/infra/commit/4e6366233246bb316e986253ec136652494a337e))
* **infra:** expose Kafka 29092 + route Kong upstreams to host-gateway in dev ([9bdcae8](https://github.com/brainwave-project/infra/commit/9bdcae898e5ca18de30c5e624ca59dd67c633287))
* **observability:** add full three-pillar observability stack ([f4b1d62](https://github.com/brainwave-project/infra/commit/f4b1d6253eec96242bc7d886011b7362d5833a78))

# 1.0.0 (2026-05-10)


### Bug Fixes

* persist Keycloak H2 data to named volume so user UUIDs survive container restarts ([3e2767f](https://github.com/brainwave-project/infra/commit/3e2767f36983a0c03406f98c0d6836c3383dab8a))
* remove prisma migrate deploy from user-hub dev startup ([1d29932](https://github.com/brainwave-project/infra/commit/1d299329c91ed6b6097f6b33fad0e2780591c705))
* switch all containers to fail-fast restart policy ([130b90b](https://github.com/brainwave-project/infra/commit/130b90b7168a3456dbdd72daf354f8aa50feb10f))


### Features

* add monitoring stack and Kong UI; restructure infra layout ([2d2a3e2](https://github.com/brainwave-project/infra/commit/2d2a3e27dff71c97b0b216d07b5282f6763f99c7))
* add prod compose config and Kong X-User-Id injection ([c1a7a91](https://github.com/brainwave-project/infra/commit/c1a7a91ba06f9f179865f6f997c5a23e43256770))
* user-hub runs migrate and seed on dev startup ([36a0153](https://github.com/brainwave-project/infra/commit/36a0153989ee6437d1745b7e4c83bca9490dbff8))
