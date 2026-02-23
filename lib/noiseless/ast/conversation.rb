# frozen_string_literal: true

module Noiseless
  module AST
    # Conversational search node for RAG (Retrieval Augmented Generation)
    # Typesense and Elasticsearch support conversational/RAG search
    class Conversation < Node
      attr_reader :model_id, :conversation_id, :system_prompt

      # @param model_id [String] The LLM model identifier
      # @param conversation_id [String, nil] ID for multi-turn conversations (optional)
      # @param system_prompt [String, nil] Custom system prompt (optional)
      def initialize(model_id:, conversation_id: nil, system_prompt: nil)
        super()
        @model_id = model_id
        @conversation_id = conversation_id
        @system_prompt = system_prompt
      end

      def multi_turn?
        !@conversation_id.nil?
      end

      def custom_prompt?
        !@system_prompt.nil?
      end
    end
  end
end
