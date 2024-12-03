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
end
