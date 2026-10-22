# frozen_string_literal: true

class SearchContractCase < Minitest::Test
  Record = Struct.new(:id, :name)

  class RecordModel
    class << self
      attr_accessor :queries

      def where(id:)
        self.queries << id
        [Record.new(1, "First"), Record.new(2, "Second")].select { id.map(&:to_s).include?(it.id.to_s) }
      end

      def find(*) = raise("Record loading must use where")
    end
  end

  class Search < Noiseless::Model
    index_name "contract_companies"
    connection :contract
  end

  class OtherSearch < Noiseless::Model
    search_index "contract_articles"
    connection :contract
  end

  class MappedSearch < Search
    index_name "contract_companies"
    connection :contract
    record_class "SearchContractCase::RecordModel"
  end

  # Use the real Adapter#search and ResponseFactory, not a synchronous mock.
  class Adapter < Noiseless::Adapter
    attr_accessor :raw_response, :error
    attr_reader :calls

    def initialize
      super
      @calls = []
      @raw_response = {
        "took" => 3,
        "hits" => {
          "total" => { "value" => 21 },
          "hits" => [hit("2"), hit("1"), hit("99")]
        }
      }
    end

    def execute_search(query, indexes:, **)
      @calls << { query: query, indexes: indexes }
      Async::Task.current.sleep(0.001)
      raise error if error

      raw_response
    end

    private

    def hit(id)
      { "_index" => "contract_companies", "_id" => id, "_score" => 1.0, "_source" => { "name" => "Company #{id}" } }
    end
  end

  def setup
    @adapter = Adapter.new
    RecordModel.queries = []
  end

  private

  def with_search_client
    client = lambda do |connection|
      assert_equal :contract, connection
      @adapter
    end
    Noiseless.connections.stub(:client, client) { yield }
  end
end
