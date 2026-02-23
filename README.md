# Noiseless

Async-first search abstraction for Ruby/Rails with multi-backend support (OpenSearch, Elasticsearch, Typesense, PostgreSQL).

## Features

- **Chainable DSL** — fluent query builder with runtime validation
- **Multi-backend** — OpenSearch, Elasticsearch, Typesense, PostgreSQL adapters
- **Async-first** — built on Ruby 3.4+ fiber scheduler with non-blocking I/O
- **HTTP/2 connection pooling** — persistent connections via `Async::Pool`
- **Rails integration** — Railtie with log subscriber and controller runtime tracking
- **Lazy loading** — adapters loaded on-demand, test files excluded from production

## Installation

```ruby
gem 'noiseless'
```

Requires Ruby >= 3.4 and Rails >= 8.1.

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

```bash
docker compose up -d
bin/test
```

Default ports match `docker-compose.yml`: Elasticsearch `:9201`, OpenSearch `:9202`, Typesense `:8109`. Override via env vars:

```bash
ELASTICSEARCH_PORT=9200 OPENSEARCH_PORT=9201 TYPESENSE_PORT=8108 bin/test
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
