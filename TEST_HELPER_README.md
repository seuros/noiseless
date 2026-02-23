# 🧪 Noiseless::TestHelper - The Ultimate Search Testing Experience

Make search testing effortless with automatic VCR cassettes, index management, debug utilities, and enhanced assertions.

## 🚀 Quick Start

### Option 1: Include TestHelper (Manual Control)
```ruby
class MySearchTest < Minitest::Test
  include Noiseless::TestHelper

  def test_searching_products
    noiseless_cassette do
      results = Search::Product.by_name("Ruby").execute
      assert_search_results(results, 5)
    end
  end
end
```

### Option 2: Inherit from TestCase (Auto-VCR)
```ruby
class Search::ProductTest < Noiseless::TestCase
  def test_basic_search
    # Auto-cassette: search/product/basic_search.yml
    results = Search::Product.by_name("Ruby").execute
    assert_search_results(results)
  end
end
```

## 📁 Auto-Generated Cassette Names

The TestHelper automatically generates meaningful cassette names:

```ruby
class Search::ProductTest < Noiseless::TestCase
  def test_searching_by_category
    # Auto-generates: search/product/searching_by_category.yml
  end
  
  def test_filtering_suppliers
    # Auto-generates: search/product/filtering_suppliers.yml  
  end
end
```

**Pattern**: `{class_path}/{method_name}.yml`
- `Search::ProductTest` → `search/product`
- `test_searching_by_category` → `searching_by_category`

## 🎬 VCR Integration

### Basic Usage
```ruby
noiseless_cassette do
  results = Search::Product.featured.execute
  assert results.any?
end
```

### Custom VCR Options
```ruby
noiseless_cassette(record: :new_episodes) do
  # Updates existing cassette with new interactions
  results = Search::Product.by_name("updated query").execute
end

noiseless_cassette(match_requests_on: [:method, :uri]) do
  # Ignore body differences in request matching
  results = Search::Product.by_name("flexible").execute
end
```

### Available VCR Options
- `record: :once` (default) - Record once, then replay
- `record: :new_episodes` - Add new interactions to existing cassette
- `record: :all` - Re-record everything
- `match_requests_on: [:method, :uri, :body]` (default)
- `allow_unused_http_interactions: false` (default)

## 🔧 Index Management

### Reset Individual Indexes
```ruby
def test_with_clean_index
  reset_index!("products")
  
  results = Search::Product.all.execute
  assert_search_empty(results)
end
```

### Reset All Known Indexes
```ruby
def test_reset_everything
  reset_all_indexes!
  
  # All search indexes are now empty
  assert_search_empty(Search::Product.all.execute)
  assert_search_empty(Search::User.all.execute)
end
```

### Class-Level Index Reset
```ruby
class MyTest < Noiseless::TestCase
  reset_test_indexes "products", "users"
  
  def test_clean_state
    # Indexes are automatically reset before each test
  end
end
```

## 🌱 Data Seeding

### Manual Seeding
```ruby
def test_with_seeded_data
  products = [
    { id: 1, name: "Ruby Book", category: "books" },
    { id: 2, name: "Python Guide", category: "books" }
  ]
  
  seed_data!("products", products)
  
  results = Search::Product.filter(:category, "books").execute
  assert_search_results(results, 2)
end
```

### Class-Level Data Setup
```ruby
class MyTest < Noiseless::TestCase
  setup_test_data "products", [
    { id: 1, name: "Test Product", category: "test" }
  ]
  
  def test_with_setup_data
    # Data is automatically seeded before each test
    results = Search::Product.filter(:category, "test").execute
    assert_search_results(results, 1)
  end
end
```

## 🐛 Debug Utilities

### Print Query Structure
```ruby
def test_debug_query
  search = Search::Product.new
    .match(:name, "laptop")
    .filter(:category, "electronics")
    .sort(:price, :asc)
  
  print_query(search)
  # Output:
  # 🔍 Generated Query AST:
  # ==============================
  # Indexes: ["products"]
  # Must clauses: 1
  # Filter clauses: 1
  # Sort clauses: 1
  # Pagination: 1/20
  # ==============================
end
```

### Generate cURL Commands
```ruby
def test_debug_curl
  search = Search::Product.featured.limit(5)
  
  curl_command = print_curl(search)
  # Output:
  # 🐛 Debug cURL Command:
  # ==================================================
  # curl -X POST "http://localhost:9200/products/_search" \
  #      -H "Content-Type: application/json" \
  #      -d '{
  #        "query": {
  #          "bool": {
  #            "filter": [{"term": {"featured": true}}]
  #          }
  #        },
  #        "size": 5
  #      }'
  # ==================================================
end
```

### Search Instrumentation
```ruby
def test_with_instrumentation
  with_search_instrumentation do
    results = Search::Product.by_name("test").execute
    # Automatically logs search events and timing
  end
end
```

## 📊 Enhanced Assertions

### Basic Result Assertions
```ruby
# Assert search has results
assert_search_results(search)

# Assert specific count
assert_search_results(search, 5)

# Assert empty results
assert_search_empty(search)

# Assert contains specific item
assert_search_includes(search, expected_product)
```

### Performance Assertions
```ruby
def test_search_speed
  search = Search::Product.featured.limit(10)
  
  # Assert search completes within 100ms
  assert_search_performance(search, 100) do
    search.execute
  end
end

def test_concurrent_performance
  searches = [
    Search::Product.by_name("ruby"),
    Search::Product.by_category("books")
  ]
  
  assert_search_performance(nil, 200) do
    searches.map(&:execute)
  end
end
```

## 🎯 Advanced Usage Examples

### A/B Testing Search Implementations
```ruby
class SearchComparisonTest < Noiseless::TestCase
  def test_compare_implementations
    query = "sustainable manufacturing"
    
    # Test existing search
    noiseless_cassette(cassette_name: "existing_search") do
      @existing_results = Company.search(query)
    end
    
    # Test Noiseless search
    noiseless_cassette(cassette_name: "noiseless_search") do
      @noiseless_results = Company::Search.by_name(query).execute
    end
    
    # Compare results
    assert_equal @existing_results.count, @noiseless_results.size
  end
end
```

### Multi-Engine Testing
```ruby
class MultiEngineTest < Noiseless::TestCase
  def test_elasticsearch_vs_typesense
    search_query = Search::Product.by_name("laptop")
    
    # Test Elasticsearch
    noiseless_cassette(cassette_name: "elasticsearch_search") do
      @es_results = search_query.execute(connection: :elasticsearch)
    end
    
    # Test Typesense  
    noiseless_cassette(cassette_name: "typesense_search") do
      @ts_results = search_query.execute(connection: :typesense)
    end
    
    # Both should return results
    assert_search_results(@es_results)
    assert_search_results(@ts_results)
  end
end
```

### Performance Regression Testing
```ruby
class PerformanceRegressionTest < Noiseless::TestCase
  def test_search_performance_baseline
    search = Search::Product.complex_query
    
    # Ensure search doesn't regress beyond baseline
    assert_search_performance(search, 150) do
      search.execute
    end
  end
  
  def test_concurrent_search_scaling
    searches = 10.times.map { Search::Product.featured }
    
    assert_search_performance(nil, 500) do
      searches.map { |s| s.execute }
    end
  end
end
```

## ⚙️ Configuration

### VCR Configuration
```ruby
# Automatically configured when TestHelper is loaded
VCR.configure do |config|
  config.cassette_library_dir = 'test/cassettes'
  config.hook_into :webmock
  
  # Sensitive data filtering
  config.filter_sensitive_data('<OPENSEARCH_HOST>') do |interaction|
    URI(interaction.request.uri).host
  end
  
  # Ignore local development hosts
  config.ignore_hosts 'localhost', '127.0.0.1', '0.0.0.0'
end
```

### Environment Variables
- `NOISELESS_VERBOSE=true` - Enable verbose test output
- `VERBOSE=true` - Alternative verbose flag
- `RAILS_ENV=test` - Auto-loads test helpers

### Test-Specific Search Configuration
```ruby
class MyTest < Noiseless::TestCase
  private

  def configure_test_connections
    Noiseless.configure do |config|
      config.connections_config[:test] = {
        adapter: :elasticsearch,
        hosts: ['http://localhost:9201']
      }
    end
  end
end
```

## 🎪 Real-World Integration Example

```ruby
# test/noiseless/company_search_test.rb
class Noiseless::CompanySearchTest < Noiseless::TestCase
  def test_supplier_search_flow
    # Auto-cassette: noiseless/company_search/supplier_search_flow.yml
    
    search = Company::Search
      .suppliers_only
      .by_country("US")
      .with_high_data_quality
      .minimum_score(80)
      .sort(:sorting_score, :desc)
      .limit(20)
    
    # Debug the query
    print_query(search)
    
    # Execute with performance monitoring
    assert_search_performance(search, 300) do
      results = search.execute
      
      # Validate results
      assert_search_results(results)
      
      # Verify all results are suppliers
      # (This would require actual result parsing)
    end
  end
  
  def test_geospatial_supplier_search
    london_lat, london_lon = 51.5074, -0.1278
    
    search = Company::Search
      .near_location(london_lat, london_lon, "50km")
      .suppliers_only
    
    results = search.execute
    assert_search_results(results, message: "Should find suppliers near London")
  end
end
```

## 🚀 Benefits

### 🎯 **Developer Experience**
- **Zero configuration** - Works out of the box
- **Automatic cassette naming** - No more manual cassette management
- **Fluent assertions** - Search-specific assertion helpers
- **Debug utilities** - Easy query debugging and curl generation

### ⚡ **Testing Efficiency**  
- **VCR integration** - Record once, replay forever
- **Index management** - Clean slate for every test
- **Performance testing** - Built-in timing assertions
- **Data seeding** - Easy test data setup

### 🔧 **Flexibility**
- **Multiple test styles** - Include helper or inherit TestCase
- **Custom VCR options** - Full control when needed
- **Multi-engine support** - Test across different search engines
- **A/B testing ready** - Compare implementations easily

## 🎉 Migration from Existing Tests

### From Raw Search Tests
```ruby
# Before
def test_search
  results = Company.search("electronics")
  assert results.any?
end

# After  
class CompanySearchTest < Noiseless::TestCase
  def test_search
    results = Company::Search.by_name("electronics").execute
    assert_search_results(results)
  end
end
```

### From Manual VCR Setup
```ruby
# Before
def test_search
  VCR.use_cassette("company_search") do
    results = Company.search("electronics")
    assert results.any?
  end
end

# After
def test_search
  # Auto-cassette based on class/method name
  results = Company::Search.by_name("electronics").execute
  assert_search_results(results)
end
```

## 📚 API Reference

### Core Methods
- `noiseless_cassette(options = {}, &block)` - Wrap code with VCR
- `reset_index!(name, adapter: :primary)` - Reset specific index
- `reset_all_indexes!(adapter: :primary)` - Reset all known indexes
- `seed_data!(index, records, adapter: :primary)` - Seed test data

### Debug Utilities
- `print_query(search)` - Print AST structure
- `print_curl(search, adapter: :primary)` - Generate curl command
- `with_search_instrumentation(&block)` - Monitor search events

### Enhanced Assertions
- `assert_search_results(search, count = nil, message = nil)`
- `assert_search_empty(search, message = nil)`
- `assert_search_includes(search, item, message = nil)`
- `assert_search_performance(search, max_ms, &block)`

### Class-Level Helpers
- `reset_test_indexes(*names)` - Auto-reset indexes per test
- `setup_test_data(index, records)` - Auto-seed data per test

---

**🎯 Ready to make search testing effortless!** The TestHelper provides everything you need for comprehensive, maintainable search tests.
