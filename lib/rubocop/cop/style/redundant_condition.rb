# frozen_string_literal: true

module RuboCop
  module Cop
    module Style
      # This cop checks for unnecessary conditional expressions.
      #
      # @example
      #   # bad
      #   a = b ? b : c
      #
      #   # good
      #   a = b || c
      #
      # @example
      #   # bad
      #   if b
      #     b
      #   else
      #     c
      #   end
      #
      #   # good
      #   b || c
      #
      #   # good
      #   if b
      #     b
      #   elsif cond
      #     c
      #   end
      #
      class RedundantCondition < Base
        include RangeHelp
        extend AutoCorrector

        MSG = 'Use double pipes `||` instead.'
        REDUNDANT_CONDITION = 'This condition is not needed.'

        def on_if(node)
          return if node.elsif_conditional?
          return unless offense?(node)

          message = message(node)

          add_offense(range_of_offense(node), message: message) do |corrector|
            if node.ternary?
              correct_ternary(corrector, node)
            elsif node.modifier_form? || !node.else_branch
              corrector.replace(node, node.if_branch.source)
            else
              corrected = make_ternary_form(node)

              corrector.replace(node, corrected)
            end
          end
        end

        private

        def message(node)
          if node.modifier_form? || !node.else_branch
            REDUNDANT_CONDITION
          else
            MSG
          end
        end

        def range_of_offense(node)
          return node.loc.expression unless node.ternary?

          range_between(node.loc.question.begin_pos, node.loc.colon.end_pos)
        end

        def offense?(node)
          _condition, _if_branch, else_branch = *node

          return false if use_if_branch?(else_branch) || use_hash_key_assignment?(else_branch)

          synonymous_condition_and_branch?(node) && !node.elsif? &&
            (node.ternary? || !else_branch.instance_of?(AST::Node) || else_branch.single_line?)
        end

        def use_if_branch?(else_branch)
          else_branch&.if_type?
        end

        def use_hash_key_assignment?(else_branch)
          else_branch&.send_type? && else_branch&.method?(:[]=)
        end

        def synonymous_condition_and_branch?(node)
          condition, if_branch, _else_branch = *node
          # e.g.
          #   if var
          #     var
          #   else
          #     'foo'
          #   end
          return true if condition == if_branch

          # e.g.
          #   if foo
          #     @value = foo
          #   else
          #     @value = another_value?
          #   end
          return true if branches_have_assignment?(node) && condition == if_branch.expression

          # e.g.
          #   if foo
          #     test.value = foo
          #   else
          #     test.value = another_value?
          #   end
          branches_have_method?(node) && condition == if_branch.first_argument
        end

        def branches_have_assignment?(node)
          _condition, if_branch, else_branch = *node

          return false unless if_branch && else_branch

          asgn_type?(if_branch) && (if_branch_variable_name = if_branch.name) &&
            asgn_type?(else_branch) && (else_branch_variable_name = else_branch.name) &&
            if_branch_variable_name == else_branch_variable_name
        end

        def asgn_type?(node)
          node.lvasgn_type? || node.ivasgn_type? || node.cvasgn_type? || node.gvasgn_type?
        end

        def branches_have_method?(node)
          _condition, if_branch, else_branch = *node

          return false unless if_branch && else_branch

          if_branch.send_type? && if_branch.arguments.count == 1 &&
            else_branch.send_type? && else_branch.arguments.count == 1 &&
            if_branch.method?(else_branch.method_name)
        end

        def else_source(else_branch)
          if branches_have_method?(else_branch.parent)
            else_source_if_has_method(else_branch)
          elsif require_parentheses?(else_branch)
            "(#{else_branch.source})"
          elsif without_argument_parentheses_method?(else_branch)
            "#{else_branch.method_name}(#{else_branch.arguments.map(&:source).join(', ')})"
          elsif branches_have_assignment?(else_branch.parent)
            else_source_if_has_assignment(else_branch)
          else
            else_branch.source
          end
        end

        def else_source_if_has_method(else_branch)
          if require_parentheses?(else_branch.first_argument)
            "(#{else_branch.first_argument.source})"
          elsif require_braces?(else_branch.first_argument)
            "{ #{else_branch.first_argument.source} }"
          else
            else_branch.first_argument.source
          end
        end

        def else_source_if_has_assignment(else_branch)
          if require_parentheses?(else_branch.expression)
            "(#{else_branch.expression.source})"
          elsif require_braces?(else_branch.expression)
            "{ #{else_branch.expression.source} }"
          else
            else_branch.expression.source
          end
        end

        def make_ternary_form(node)
          _condition, if_branch, else_branch = *node
          ternary_form = [if_branch.source, else_source(else_branch)].join(' || ')

          if node.parent&.send_type?
            "(#{ternary_form})"
          else
            ternary_form
          end
        end

        def correct_ternary(corrector, node)
          corrector.replace(range_of_offense(node), '||')

          return unless node.else_branch.range_type?

          corrector.wrap(node.else_branch, '(', ')')
        end

        def require_parentheses?(node)
          (node.basic_conditional? && node.modifier_form?) ||
            node.range_type? ||
            node.rescue_type? ||
            (node.respond_to?(:semantic_operator?) && node.semantic_operator?)
        end

        def require_braces?(node)
          node.hash_type? && !node.braces?
        end

        def without_argument_parentheses_method?(node)
          node.send_type? && !node.arguments.empty? &&
            !node.parenthesized? && !node.operator_method? && !node.assignment_method?
        end
      end
    end
  end
end
