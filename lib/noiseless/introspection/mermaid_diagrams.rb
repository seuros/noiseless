# frozen_string_literal: true

module Noiseless
  module Introspection
    # Mermaid renderings of an AST and of a query's execution flow.
    class MermaidDiagrams
      def self.generate_flow_diagram(explanation)
        # Create a sequence diagram showing the query execution flow
        diagram = "sequenceDiagram\n".dup
        diagram << "    participant Client\n"
        diagram << "    participant Adapter\n"
        diagram << "    participant Engine\n"

        explanation[:execution_plan].each do |step|
          diagram << case step[:description]
                     when /validate/i
                       "    Client->>Adapter: #{step[:description]}\n"
                     when /convert/i, /format/i
                       "    Adapter->>Adapter: #{step[:description]}\n"
                     when /execute/i, /query/i
                       "    Adapter->>Engine: #{step[:description]}\n"
                     else
                       "    Engine->>Adapter: #{step[:description]}\n"
                     end
        end

        diagram << "    Adapter->>Client: Return results\n"
        diagram
      end

      # New methods using your diagram/mermaid gems
      def self.ast_to_mermaid_flowchart(ast_node)
        return "# Mermaid diagrams require 'diagrams' and 'mermaid' gems\n# Add to Gemfile: gem 'diagrams'; gem 'mermaid'" unless DIAGRAMS_AVAILABLE

        diagram = Diagrams::FlowchartDiagram.new(version: "1.0")

        # Convert AST structure to flowchart nodes and edges
        add_ast_node_to_flowchart(diagram, ast_node, "root")

        diagram.to_mermaid
      end

      def self.ast_to_mermaid_class_diagram(ast_node)
        return "# Mermaid diagrams require 'diagrams' and 'mermaid' gems\n# Add to Gemfile: gem 'diagrams'; gem 'mermaid'" unless DIAGRAMS_AVAILABLE

        diagram = Diagrams::ClassDiagram.new(version: "1.0")

        # Create a class representation of the AST structure
        root_class = Diagrams::Elements::ClassEntity.new(
          name: ast_node.class.name.split("::").last,
          attributes: ast_node.instance_variables.map do |var|
            "#{var.to_s.delete('@')}: #{ast_node.instance_variable_get(var).class.name.split('::').last}"
          end,
          methods: ast_node.public_methods(false).map { |method| "+#{method}()" }
        )

        diagram.add_class(root_class)

        # Add child nodes as related classes
        add_ast_children_to_class_diagram(diagram, ast_node, root_class.name)

        diagram.to_mermaid
      end

      def self.add_ast_node_to_flowchart(diagram, node, node_id)
        # Add current node
        flowchart_node = Diagrams::Elements::Node.new(
          id: node_id,
          label: node.class.name.split("::").last.to_s
        )
        diagram.add_node(flowchart_node)

        # Add child nodes and connect them
        return unless node.respond_to?(:instance_variables)

        node.instance_variables.each_with_index do |var, _index|
          child_value = node.instance_variable_get(var)

          if child_value.is_a?(Noiseless::AST::Node)
            child_id = "#{node_id}_#{var.to_s.delete('@')}"
            add_ast_node_to_flowchart(diagram, child_value, child_id)

            edge = Diagrams::Elements::Edge.new(
              source_id: node_id,
              target_id: child_id,
              label: var.to_s.delete("@")
            )
            diagram.add_edge(edge)
          elsif child_value.is_a?(Array) && child_value.any?(Noiseless::AST::Node)
            child_value.each_with_index do |item, item_index|
              next unless item.is_a?(Noiseless::AST::Node)

              child_id = "#{node_id}_#{var.to_s.delete('@')}_#{item_index}"
              add_ast_node_to_flowchart(diagram, item, child_id)

              edge = Diagrams::Elements::Edge.new(
                source_id: node_id,
                target_id: child_id,
                label: "#{var.to_s.delete('@')}[#{item_index}]"
              )
              diagram.add_edge(edge)
            end
          end
        end
      end

      def self.add_ast_children_to_class_diagram(diagram, node, parent_class_name)
        return unless node.respond_to?(:instance_variables)

        node.instance_variables.each do |var|
          child_value = node.instance_variable_get(var)

          next unless child_value.is_a?(Noiseless::AST::Node)

          child_class_name = child_value.class.name.split("::").last

          # Add child class if not already added
          unless diagram.classes.any? { |c| c.name == child_class_name }
            child_class = Diagrams::Elements::ClassEntity.new(
              name: child_class_name,
              attributes: child_value.instance_variables.map do |cv|
                "#{cv.to_s.delete('@')}: #{child_value.instance_variable_get(cv).class.name.split('::').last}"
              end
            )
            diagram.add_class(child_class)
          end

          # Add relationship
          relationship = Diagrams::Elements::Relationship.new(
            source_class_name: parent_class_name,
            target_class_name: child_class_name,
            type: "composition",
            label: var.to_s.delete("@")
          )
          diagram.add_relationship(relationship)

          # Recursively add children
          add_ast_children_to_class_diagram(diagram, child_value, child_class_name)
        end
      end
    end
  end
end
