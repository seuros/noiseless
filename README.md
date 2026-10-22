# Noiseless

Async-first search abstraction for Rails with multi-backend support (OpenSearch, Elasticsearch, Typesense, PostgreSQL).

## Features

- **Chainable DSL** — fluent query builder with runtime validation
- **Multi-backend** — OpenSearch, Elasticsearch, Typesense, PostgreSQL adapters
- **Async-first** — built on Ruby 4.0+ fiber scheduler with non-blocking I/O
- **HTTP/2 connection pooling** — persistent connections via `Async::Pool`
- **Rails integration** — Railtie with log subscriber and controller runtime tracking
- **Lazy loading** — adapters loaded on-demand, test files excluded from production

## Installation

```ruby
gem "noiseless"
```

`noiseless` is a Rails gem. It requires Ruby >= 4.0 and Rails >= 8.1.

## Configuration

Create `config/noiseless.yml`:

```yaml
development:
  default: primary
  connections:
    primary:
      adapter: elasticsearch
      hosts:
        - http://localhost:9201
    opensearch:
      adapter: open_search
      hosts:
        - http://localhost:9202
    typesense:
      adapter: typesense
      hosts:
        - http://localhost:8109
    postgresql:
      adapter: postgresql

production:
  default: primary
  connections:
    primary:
      adapter: opensearch
      hosts:
        - <%= ENV['OPENSEARCH_URL'] %>
    typesense:
      adapter: typesense
      hosts:
        - <%= ENV['TYPESENSE_URL'] %>
    postgresql:
      adapter: postgresql
```

## Usage

### Defining a Search

```ruby
class Company::Search < Noiseless::Model
  index_name 'companies'

  def by_name(name)
    multi_match(name, [:name, :name_aliases])
  end

  def suppliers_only
    filter(:company_type, 'supplier')
  end
end
```

### Executing Searches

All `.execute` calls return `Async::Task` objects. Use `Sync` to wait for results, or use the `_sync` convenience methods:

```ruby
# Convenience method (recommended for simple cases)
results = Company::Search.new.by_name('tech').execute_sync

# Class-level convenience
results = Company::Search.search_sync do |s|
  s.match(:name, 'tech')
  s.limit(10)
end

# Explicit Sync block
results = Sync do
  Company::Search.new
    .by_name('technology')
    .suppliers_only
    .limit(20)
    .execute
    .wait
end
```

### Concurrent Searches

```ruby
Async do |task|
  companies_task = Company::Search.new.match(:name, 'tech').execute
  products_task  = Product::Search.new.match(:name, 'tech').execute

  companies = companies_task.wait
  products  = products_task.wait
end
```

For best performance, run independent searches concurrently within a single `Async` block rather than creating separate `Sync` blocks per search.

### Loading Database Records

Search classes return search results by default. To load database records, configure
the record model explicitly and request `response_type: :records`:

```ruby
class Company::Search < Noiseless::Model
  index_name 'companies'
  record_class 'Company' # A Class is also accepted; strings resolve lazily.
end

records = Company::Search.search_sync(response_type: :records) do |s|
  s.match(:name, 'tech')
end
records.to_a # Company records in search relevance order

# The instance API supports the same option.
Company::Search.new.match(:name, 'tech').execute_sync(response_type: :records)
```

`record_class` is inherited and does not change the default response type. Index
names are not used to infer record classes: aliases and versioned indexes need
not match table names. Requesting `:records` without a model supporting `.where`
raises `ArgumentError`, even when the search has no hits. Records missing from
the database are omitted; search totals still describe backend hits.

### Pagination and Multi-model Search

The paginator executes lazily and waits for its response when results or totals
are accessed. Multi-search also waits and returns a `MultiSearchResponse`, not
an `Async::Task`. Both work inside an existing async context.

```ruby
page = Company::Search.page(2).per(10)
page.to_a
page.total_count

response = Noiseless.multi_search(models: [Company::Search, Product::Search]) do |s|
  s.match(:name, 'tech')
  s.limit(10)
end
response.results_for_model(Company::Search)
response.records_for_model(Company::Search) # Uses its configured record_class.
```

### Advanced Queries

```ruby
results = Company::Search.new
  .match(:name, 'electronics')
  .filter(:status, 'active')
  .geo_distance(:location, lat: 40.7128, lon: -74.0060, distance: '50km')
  .sort(:created_at, :desc)
  .paginate(page: 1, per_page: 10)
  .execute_sync
```

### Rails Integration

```ruby
class CompaniesController < ApplicationController
  def search
    @results = Company::Search.new
      .by_name(params[:q])
      .limit(20)
      .execute_sync

    render json: @results
  end
end
```

## Testing

Add to `test/test_helper.rb`:

```ruby
require 'noiseless/test_helper'
require 'noiseless/test_case'
```

### With Noiseless::TestCase (automatic VCR cassettes)

```ruby
class CompanySearchTest < Noiseless::TestCase
  def test_search_by_name
    # Cassette auto-named: company_search/search_by_name
    search = Company::Search.new.by_name('test')
    assert_search_results(search)
  end
end
```

### With manual VCR control

```ruby
class CompanySearchTest < ActiveSupport::TestCase
  include Noiseless::TestHelper

  def test_custom_search
    noiseless_cassette(record: :new_episodes) do
      results = Company::Search.new.by_name('test').execute_sync
      assert results.any?
    end
  end
end
```

### Running Tests Locally

Run the pagination, multi-search, and record-loading unit tests without services:

```bash
bundle exec ruby -Itest -Ilib -e 'ARGV.each { require_relative it }' \
  test/{search_pagination,multi_search,record_response,active_record_response,postgresql_search_contract,query_contract}_test.rb
```

For the full integration suite:

```bash
docker compose up -d postgres elasticsearch opensearch typesense
bin/test
```

`bin/test` expects all four local services from `docker-compose.yml`, including PostgreSQL on `:5432`.
Default ports match `docker-compose.yml`: PostgreSQL `:5432`, Elasticsearch `:9201`, OpenSearch `:9202`, Typesense `:8109`. Override via env vars:

```bash
ELASTICSEARCH_PORT=9200 OPENSEARCH_PORT=9201 TYPESENSE_PORT=8108 bin/test
```

For a release smoke test that does not require the dummy app or local services:

```bash
bundle exec rake release:check
```

## Debug Mode

```ruby
ENV['NOISELESS_VERBOSE'] = 'true'
```

## Contributing

1. Follow Rails conventions for code organization
2. Test helpers must remain separate from core functionality
3. Add tests for new features using the provided test utilities

## License

BSD 3-Clause License — See [LICENSE.txt](LICENSE.txt)
