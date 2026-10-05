# Changelog

## [0.8.0](https://github.com/seuros/noiseless/compare/noiseless/v0.7.2...noiseless/v0.8.0) (2026-10-05)


### ⚠ BREAKING CHANGES

* **typesense:** Typesense searches go through POST /multi_search, bulk uses JSONL import with upsert, updates use PATCH, existence checks use GET, keyword fields map to string[], and hybrid search requires fields:.
* **elasticsearch:** Requires Elasticsearch 9.4 or later for base64 query vectors. Hybrid search is a weighted bool.should of multi_match and knn instead of rank.rrf, and knn applies the query filters.
* **opensearch:** Vector and hybrid search use the native knn and hybrid queries with an RRF pipeline, point_in_time_search is replaced by each_page, and the rules API drives workload-management auto-tagging.
* **typesense:** join no longer takes on:; the relation comes from a reference: field in the mapping.
* point-in-time pagination for Elasticsearch and OpenSearch
* move to async 2.46, async-http 0.105 and Rails 8.1.4
* require Ruby 4.0

### Features

* **elasticsearch:** move to Elasticsearch 9.5.4 and base64 vectors ([042bc0e](https://github.com/seuros/noiseless/commit/042bc0e28474eac0d8a62540bc3360b5260b8257))
* move to async 2.46, async-http 0.105 and Rails 8.1.4 ([30b2907](https://github.com/seuros/noiseless/commit/30b2907e9f6d18d2575a5f248d0a0282b9a628f7))
* **opensearch:** move to OpenSearch 3.9.0 and its native vector APIs ([042bc0e](https://github.com/seuros/noiseless/commit/042bc0e28474eac0d8a62540bc3360b5260b8257))
* point-in-time pagination for Elasticsearch and OpenSearch ([cedc3a7](https://github.com/seuros/noiseless/commit/cedc3a756c311685e9f3ab1f8b695fc2829fb78d))
* require Ruby 4.0 ([1f8fef2](https://github.com/seuros/noiseless/commit/1f8fef2aae7b26e24673801a2743665da536ee09))
* **typesense:** move to Typesense 30.2 and its current APIs ([042bc0e](https://github.com/seuros/noiseless/commit/042bc0e28474eac0d8a62540bc3360b5260b8257))
* **typesense:** resolve joins through schema references ([042bc0e](https://github.com/seuros/noiseless/commit/042bc0e28474eac0d8a62540bc3360b5260b8257))
* wrap mapped vector fields on single-document writes ([acececc](https://github.com/seuros/noiseless/commit/acececccdc41231d128548213aab35a9bab089d7))


### Bug Fixes

* bring PostgreSQL adapter results in line with ES/OpenSearch ([dea19cf](https://github.com/seuros/noiseless/commit/dea19cfb22b501107262109cdba8f6170c2ff6d3)), closes [#13](https://github.com/seuros/noiseless/issues/13)
* keep times and dates valid in request bodies under json 3 ([ae27020](https://github.com/seuros/noiseless/commit/ae27020536af8399d680d5a0db07370dfa4855d6))
* **postgresql:** make hybrid search work and reachable from the DSL ([e533656](https://github.com/seuros/noiseless/commit/e533656e9e0d4e3607fd517755c83fa571f46c91))
* **postgresql:** stop logging awaited search failures as unhandled ([721c8d0](https://github.com/seuros/noiseless/commit/721c8d01aca0ba1e1939fd7b42eb578db3648ebb))
* quote and fail closed in PostgreSQL geo filter ([#17](https://github.com/seuros/noiseless/issues/17)) ([4ff4227](https://github.com/seuros/noiseless/commit/4ff4227e540e3a6e1d8fe7fd77be0c89c3b64db5)), closes [#9](https://github.com/seuros/noiseless/issues/9)
* raise on PostgreSQL and Typesense search failures ([7b1c7c5](https://github.com/seuros/noiseless/commit/7b1c7c5ce28794379bcea6c09f3b0956719c1ff1)), closes [#11](https://github.com/seuros/noiseless/issues/11)
* recreate the index on reindex and honour refresh ([7d6f6c6](https://github.com/seuros/noiseless/commit/7d6f6c66b147ff9b9ae9f394c36ec27d0ba252d2)), closes [#12](https://github.com/seuros/noiseless/issues/12)
* reject non-numeric embeddings before they reach SQL ([#15](https://github.com/seuros/noiseless/issues/15)) ([37681c7](https://github.com/seuros/noiseless/commit/37681c70602b32c61b8eb3f5da8dc104ad3e1c39)), closes [#10](https://github.com/seuros/noiseless/issues/10)
* repair public API defects in paginate, indices, jobs and callbacks ([c8d2250](https://github.com/seuros/noiseless/commit/c8d22503203f2f2bb5d94670e95c667a830b3d6e)), closes [#14](https://github.com/seuros/noiseless/issues/14)
* surface document write failures to callbacks and jobs ([3119ce9](https://github.com/seuros/noiseless/commit/3119ce991a58ac24840206f70e73dbe9439b1ddf))
* **typesense:** send searches to the requested collection with query_by ([8aae403](https://github.com/seuros/noiseless/commit/8aae403b80288d4c4f8f947de226d6f0ce2808e0))
* **typesense:** send times as epoch seconds and keyword fields as arrays ([788ea99](https://github.com/seuros/noiseless/commit/788ea99b3cb0bfbe07130f2d07255d986bbe39a9))

## [0.7.2](https://github.com/seuros/noiseless/compare/noiseless/v0.7.1...noiseless/v0.7.2) (2026-09-11)


### Bug Fixes

* array filter semantics and fail-closed clauses for PostgreSQL adapter ([0c06698](https://github.com/seuros/noiseless/commit/0c06698e5759ada1272a25fe75c067c61b44a308))

## [0.7.1](https://github.com/seuros/noiseless/compare/noiseless/v0.7.0...noiseless/v0.7.1) (2026-09-04)


### Bug Fixes

* harden PostgreSQL adapter for production query paths ([606d77e](https://github.com/seuros/noiseless/commit/606d77eabe55661fddec0b578207e835372ed6d4))

## [0.7.0](https://github.com/seuros/noiseless/compare/noiseless/v0.6.0...noiseless/v0.7.0) (2026-09-02)


### Features

* wall-clock request_timeout for HTTP transport ([f0e4cc6](https://github.com/seuros/noiseless/commit/f0e4cc63bd64797e12c701c6f80df0d8990cc182))

## [0.6.0](https://github.com/seuros/noiseless/compare/noiseless-v0.5.0...noiseless/v0.6.0) (2026-08-05)


### Features

* global auto_index kill switch via config and NOISELESS_AUTO_INDEX env ([d095167](https://github.com/seuros/noiseless/commit/d0951676fa87306d3501c5c0fc4939a26afcfd78))
