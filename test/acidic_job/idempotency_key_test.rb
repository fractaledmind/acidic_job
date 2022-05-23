# frozen_string_literal: true

require "test_helper"
require_relative "../support/test_case"

class TestIdempotencyKey < TestCase
  # with job_id acidic identifier
  #   def test_return_job_id_from_hash_when_identifier_job_id
  #     value = AcidicJob::IdempotencyKey.new(:job_id).value_for({ "job_id" => "ID" })
  #
  #     assert_equal "ID", value
  #   end
  #
  #   def test_return_jid_from_hash_when_identifier_job_id
  #     value = AcidicJob::IdempotencyKey.new(:job_id).value_for({ "jid" => "ID" })
  #
  #     assert_equal "ID", value
  #   end
  #
  #   def test_return_job_id_from_obj_when_identifier_job_id
  #     job = Struct.new(:job_id)
  #     value = AcidicJob::IdempotencyKey.new(:job_id).value_for(job.new("ID"))
  #
  #     assert_equal "ID", value
  #   end
  #
  #   def test_return_jid_from_obj_when_identifier_job_id
  #     job = Struct.new(:jid)
  #     value = AcidicJob::IdempotencyKey.new(:job_id).value_for(job.new("ID"))
  #
  #     assert_equal "ID", value
  #   end
  #
  #   def test_return_sha_digest_from_hash_with_worker_when_identifier_job_id
  #     value = AcidicJob::IdempotencyKey.new(:job_id).value_for({ "worker" => "SomeClass" })
  #
  #     assert_equal "2370d4813b8b5985f2363681034e3fc312988344", value
  #   end
  #
  #   def test_return_sha_digest_from_hash_with_job_class_when_identifier_job_id
  #     value = AcidicJob::IdempotencyKey.new(:job_id).value_for({ "job_class" => "SomeClass" })
  #
  #     assert_equal "2370d4813b8b5985f2363681034e3fc312988344", value
  #   end
  #
  #   def test_return_sha_digest_from_object_when_identifier_job_id
  #     job = Struct.new(:class)
  #     klass = Struct.new(:name)
  #     value = AcidicJob::IdempotencyKey.new(:job_id).value_for(job.new(klass.new("SomeClass")))
  #
  #     assert_equal "2370d4813b8b5985f2363681034e3fc312988344", value
  #   end
  #
  #   # with job_args acidic identifier
  #
  #   def test_return_job_id_from_hash_when_identifier_job_args
  #     value = AcidicJob::IdempotencyKey.new(:job_args).value_for({ "job_id" => "ID" })
  #
  #     assert_equal "bf21a9e8fbc5a3846fb05b4fa0859e0917b2202f", value
  #   end
  #
  #   def test_return_jid_from_hash_when_identifier_job_args
  #     value = AcidicJob::IdempotencyKey.new(:job_args).value_for({ "jid" => "ID" })
  #
  #     assert_equal "bf21a9e8fbc5a3846fb05b4fa0859e0917b2202f", value
  #   end
  #
  #   def test_return_job_id_from_obj_when_identifier_job_args
  #     job = Struct.new(:job_id)
  #     value = AcidicJob::IdempotencyKey.new(:job_args).value_for(job.new("ID"))
  #
  #     assert_equal "bf21a9e8fbc5a3846fb05b4fa0859e0917b2202f", value
  #   end
  #
  #   def test_return_jid_from_obj_when_identifier_job_args
  #     job = Struct.new(:jid)
  #     value = AcidicJob::IdempotencyKey.new(:job_args).value_for(job.new("ID"))
  #
  #     assert_equal "bf21a9e8fbc5a3846fb05b4fa0859e0917b2202f", value
  #   end
  #
  #   def test_return_sha_digest_from_hash_with_worker_when_identifier_job_args
  #     value = AcidicJob::IdempotencyKey.new(:job_args).value_for({ "worker" => "SomeClass" })
  #
  #     assert_equal "2370d4813b8b5985f2363681034e3fc312988344", value
  #   end
  #
  #   def test_return_sha_digest_from_hash_with_job_class_when_identifier_job_args
  #     value = AcidicJob::IdempotencyKey.new(:job_args).value_for({ "job_class" => "SomeClass" })
  #
  #     assert_equal "2370d4813b8b5985f2363681034e3fc312988344", value
  #   end
  #
  #   def test_return_sha_digest_from_object_when_identifier_job_args
  #     job = Struct.new(:class)
  #     klass = Struct.new(:name)
  #     value = AcidicJob::IdempotencyKey.new(:job_args).value_for(job.new(klass.new("SomeClass")))
  #
  #     assert_equal "2370d4813b8b5985f2363681034e3fc312988344", value
  #   end
  #
  #   # with proc acidic identifier
  #
  #   def test_return_identifier_proc_value_from_args
  #     value = AcidicJob::IdempotencyKey.new(->(int) { int**2 }).value_for({ "job_id" => "ID" }, 2)
  #
  #     assert_equal "1b6453892473a467d07372d45eb05abc2031647a", value
  #   end
  #
  #   def test_return_identifier_proc_value_from_kwargs
  #     value = AcidicJob::IdempotencyKey.new(->(int:) { int**2 }).value_for({ "job_id" => "ID" }, int: 2)
  #
  #     assert_equal "1b6453892473a467d07372d45eb05abc2031647a", value
  #   end
end
