# frozen_string_literal: true

module RuboCop
  module Cop
    module Rails
      # This cop identifies places where manually constructed SQL
      # in `where` can be replaced with `where(attribute: value)`.
      #
      # @example
      #   # bad
      #   User.where('name = ?', 'Gabe')
      #   User.where('name = :name', name: 'Gabe')
      #   User.where('name IS NULL')
      #   User.where('name IN (?)', ['john', 'jane'])
      #   User.where('name IN (:names)', names: ['john', 'jane'])
      #
      #   # good
      #   User.where(name: 'Gabe')
      #   User.where(name: nil)
      #   User.where(name: ['john', 'jane'])
      class WhereEquals < Cop
        include RangeHelp

        MSG = 'Use `%<good_method>s` instead of manually constructing SQL.'

        def_node_matcher :where_method_call?, <<~PATTERN
          {
            (send _ :where (array $str_type? $_ ?))
            (send _ :where $str_type? $_ ?)
          }
        PATTERN

        def on_send(node)
          where_method_call?(node) do |template_node, value_node|
            value_node = value_node.first

            range = offense_range(node)

            column_and_value = extract_column_and_value(template_node, value_node)
            return unless column_and_value

            good_method = build_good_method(*column_and_value)
            message = format(MSG, good_method: good_method)

            add_offense(node, location: range, message: message)
          end
        end

        def autocorrect(node)
          where_method_call?(node) do |template_node, value_node|
            value_node = value_node.first

            lambda do |corrector|
              range = offense_range(node)

              column, value = *extract_column_and_value(template_node, value_node)
              replacement = build_good_method(column, value)

              corrector.replace(range, replacement)
            end
          end
        end

        EQ_ANONYMOUS_RE = /\A([\w.]+)\s+=\s+\?\z/.freeze             # column = ?
        IN_ANONYMOUS_RE = /\A([\w.]+)\s+IN\s+\(\?\)\z/i.freeze       # column IN (?)
        EQ_NAMED_RE     = /\A([\w.]+)\s+=\s+:(\w+)\z/.freeze         # column = :column
        IN_NAMED_RE     = /\A([\w.]+)\s+IN\s+\(:(\w+)\)\z/i.freeze   # column IN (:column)
        IS_NULL_RE      = /\A([\w.]+)\s+IS\s+NULL\z/i.freeze         # column IS NULL

        private

        def offense_range(node)
          range_between(node.loc.selector.begin_pos, node.loc.expression.end_pos)
        end

        def extract_column_and_value(template_node, value_node)
          value =
            case template_node.value
            when EQ_ANONYMOUS_RE, IN_ANONYMOUS_RE
              value_node.source
            when EQ_NAMED_RE, IN_NAMED_RE
              return unless value_node.hash_type?

              pair = value_node.pairs.find { |p| p.key.value.to_sym == Regexp.last_match(2).to_sym }
              pair.value.source
            when IS_NULL_RE
              'nil'
            else
              return
            end

          [Regexp.last_match(1), value]
        end

        def build_good_method(column, value)
          if column.include?('.')
            "where('#{column}' => #{value})"
          else
            "where(#{column}: #{value})"
          end
        end
      end
    end
  end
end