# frozen_string_literal: true

require "test_helper"

class AcidicJob::ErrorsTest < ActiveJob::TestCase
  test "redefining workflow error does take no arguments" do
    assert AcidicJob::RedefiningWorkflowError.new
  end

  test "redefining workflow error does take one argument" do
    assert AcidicJob::RedefiningWorkflowError.new("test")
  end

  test "redefining workflow error doesn't take two arguments" do
    assert_raises(ArgumentError, "wrong number of arguments (given 1, expected 2)") do
      AcidicJob::RedefiningWorkflowError.new("test", "test")
    end
  end

  test "undefined workflow error does take no arguments" do
    assert AcidicJob::UndefinedWorkflowBlockError.new
  end

  test "undefined workflow error does take one argument" do
    assert AcidicJob::UndefinedWorkflowBlockError.new("test")
  end

  test "undefined workflow error doesn't take two arguments" do
    assert_raises(ArgumentError, "wrong number of arguments (given 1, expected 2)") do
      AcidicJob::UndefinedWorkflowBlockError.new("test", "test")
    end
  end

  test "invalid workflow error does take no arguments" do
    assert AcidicJob::InvalidWorkflowBlockError.new
  end

  test "invalid workflow error does take one argument" do
    assert AcidicJob::InvalidWorkflowBlockError.new("test")
  end

  test "invalid workflow error doesn't take two arguments" do
    assert_raises(ArgumentError, "wrong number of arguments (given 1, expected 2)") do
      AcidicJob::InvalidWorkflowBlockError.new("test", "test")
    end
  end

  test "missing steps error does take no arguments" do
    assert AcidicJob::MissingStepsError.new
  end

  test "missing steps error does take one argument" do
    assert AcidicJob::MissingStepsError.new("test")
  end

  test "missing steps error doesn't take two arguments" do
    assert_raises(ArgumentError, "wrong number of arguments (given 1, expected 2)") do
      AcidicJob::MissingStepsError.new("test", "test")
    end
  end

  test "argument mismatch error doesn't take no arguments" do
    assert_raises(ArgumentError, "wrong number of arguments (given 0, expected 2)") do
      AcidicJob::ArgumentMismatchError.new
    end
  end

  test "argument mismatch error doesn't take one argument" do
    assert_raises(ArgumentError, "wrong number of arguments (given 1, expected 2)") do
      AcidicJob::ArgumentMismatchError.new("test")
    end
  end

  test "argument mismatch error does take two arguments" do
    assert AcidicJob::ArgumentMismatchError.new("test", "test")
  end

  test "definition mismatch error doesn't take no arguments" do
    assert_raises(ArgumentError, "wrong number of arguments (given 0, expected 2)") do
      AcidicJob::DefinitionMismatchError.new
    end
  end

  test "definition mismatch error doesn't take one argument" do
    assert_raises(ArgumentError, "wrong number of arguments (given 1, expected 2)") do
      AcidicJob::DefinitionMismatchError.new("test")
    end
  end

  test "definition mismatch error does take two arguments" do
    assert AcidicJob::DefinitionMismatchError.new("test", "test")
  end

  test "undefined step error doesn't take no arguments" do
    assert_raises(ArgumentError, "wrong number of arguments (given 0, expected 2)") do
      AcidicJob::UndefinedStepError.new
    end
  end

  test "undefined step error does take one argument" do
    assert AcidicJob::UndefinedStepError.new("test")
  end

  test "undefined step error doesn't take two arguments" do
    assert_raises(ArgumentError, "wrong number of arguments (given 2, expected 1)") do
      AcidicJob::UndefinedStepError.new("test", "test")
    end
  end

  test "succeeded step error doesn't take no arguments" do
    assert_raises(ArgumentError, "wrong number of arguments (given 0, expected 2)") do
      AcidicJob::SucceededStepError.new
    end
  end

  test "succeeded step error does take one argument" do
    assert AcidicJob::SucceededStepError.new("test")
  end

  test "succeeded step error doesn't take two arguments" do
    assert_raises(ArgumentError, "wrong number of arguments (given 2, expected 1)") do
      AcidicJob::SucceededStepError.new("test", "test")
    end
  end

  test "undefined method error doesn't take no arguments" do
    assert_raises(ArgumentError, "wrong number of arguments (given 0, expected 2)") do
      AcidicJob::UndefinedMethodError.new
    end
  end

  test "undefined method error does take one argument" do
    assert AcidicJob::UndefinedMethodError.new("test")
  end

  test "undefined method error doesn't take two arguments" do
    assert_raises(ArgumentError, "wrong number of arguments (given 2, expected 1)") do
      AcidicJob::UndefinedMethodError.new("test", "test")
    end
  end

  test "invalid method error doesn't take no arguments" do
    assert_raises(ArgumentError, "wrong number of arguments (given 0, expected 2)") do
      AcidicJob::InvalidMethodError.new
    end
  end

  test "invalid method error does take one argument" do
    assert AcidicJob::InvalidMethodError.new("test")
  end

  test "invalid method error doesn't take two arguments" do
    assert_raises(ArgumentError, "wrong number of arguments (given 2, expected 1)") do
      AcidicJob::InvalidMethodError.new("test", "test")
    end
  end

  # ============================================
  # Error message tests (to exercise #message methods)
  # ============================================

  test "SucceededStepError message includes step name" do
    error = AcidicJob::SucceededStepError.new("my_step")
    assert_match(/my_step/, error.message)
    assert_match(/already recorded.*succeeded/i, error.message)
  end

  test "InvalidMethodError message includes step name" do
    error = AcidicJob::InvalidMethodError.new("bad_step")
    assert_match(/bad_step/, error.message)
    assert_match(/cannot expect arguments/i, error.message)
  end

  test "DoublePluginCallError takes plugin and step arguments" do
    error = AcidicJob::DoublePluginCallError.new(AcidicJob::Plugins::TransactionalStep, "my_step")
    assert_match(/TransactionalStep/, error.message)
    assert_match(/my_step/, error.message)
    assert_match(/multiple times/i, error.message)
  end

  test "DoublePluginCallError works with module plugin" do
    module TestPluginModule
      extend self
      def keyword = :test
    end

    error = AcidicJob::DoublePluginCallError.new(TestPluginModule, "step_name")
    assert_match(/TestPluginModule/, error.message)
    assert_match(/step_name/, error.message)
  end

  test "DoublePluginCallError works with class instance plugin" do
    plugin_class = Class.new do
      def self.name = "MyPluginClass"
    end
    plugin_instance = plugin_class.new

    error = AcidicJob::DoublePluginCallError.new(plugin_instance, "step_name")
    assert_match(/MyPluginClass/, error.message)
  end

  test "MissingPluginCallError takes plugin and step arguments" do
    error = AcidicJob::MissingPluginCallError.new(AcidicJob::Plugins::TransactionalStep, "my_step")
    assert_match(/TransactionalStep/, error.message)
    assert_match(/my_step/, error.message)
    assert_match(/failed to call/i, error.message)
  end

  test "MissingPluginCallError works with module plugin" do
    module AnotherTestPlugin
      extend self
      def keyword = :another
    end

    error = AcidicJob::MissingPluginCallError.new(AnotherTestPlugin, "some_step")
    assert_match(/AnotherTestPlugin/, error.message)
    assert_match(/some_step/, error.message)
  end

  test "MissingPluginCallError works with class instance plugin" do
    plugin_class = Class.new do
      def self.name = "InstancePlugin"
    end
    plugin_instance = plugin_class.new

    error = AcidicJob::MissingPluginCallError.new(plugin_instance, "step")
    assert_match(/InstancePlugin/, error.message)
  end
end
