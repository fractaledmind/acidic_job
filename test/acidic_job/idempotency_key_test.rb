# frozen_string_literal: true

require "test_helper"

class TestIdempotencyKey < Minitest::Test
  def test_return_job_id_from_hash
    value = AcidicJob::IdempotencyKey.value_for({ "job_id" => "ID" })

    assert_equal "ID", value
  end

  def test_return_jid_from_hash
    value = AcidicJob::IdempotencyKey.value_for({ "jid" => "ID" })

    assert_equal "ID", value
  end

  def test_return_job_id_from_obj
    job = Struct.new(:job_id)
    value = AcidicJob::IdempotencyKey.value_for(job.new("ID"))

    assert_equal "ID", value
  end

  def test_return_jid_from_obj
    job = Struct.new(:jid)
    value = AcidicJob::IdempotencyKey.value_for(job.new("ID"))

    assert_equal "ID", value
  end

  def test_return_sha_digest_from_hash_with_worker
    value = AcidicJob::IdempotencyKey.value_for({ "worker" => "SomeClass" })

    assert_equal "3448676ac7043b5378f25239cc0d7b8fbe9c23c2", value
  end

  def test_return_sha_digest_from_hash_with_job_class
    value = AcidicJob::IdempotencyKey.value_for({ "job_class" => "SomeClass" })

    assert_equal "3448676ac7043b5378f25239cc0d7b8fbe9c23c2", value
  end

  def test_return_sha_digest_from_object
    job = Struct.new(:class) # rubocop:disable Lint/StructNewOverride
    klass = Struct.new(:name)
    value = AcidicJob::IdempotencyKey.value_for(job.new(klass.new("SomeClass")))

    assert_equal "3448676ac7043b5378f25239cc0d7b8fbe9c23c2", value
  end
end
