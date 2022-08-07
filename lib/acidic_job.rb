# frozen_string_literal: true

require_relative "acidic_job/version"
require_relative "acidic_job/errors"
require_relative "acidic_job/logger"
require_relative "acidic_job/arguments"
require_relative "acidic_job/serializer"
require_relative "acidic_job/workflow_builder"
require_relative "acidic_job/idempotency_key"
require_relative "acidic_job/recovery_point"
require_relative "acidic_job/finished_point"
require_relative "acidic_job/run"
require_relative "acidic_job/workflow_step"
require_relative "acidic_job/workflow"
require_relative "acidic_job/processor"
require_relative "acidic_job/mixin"
require_relative "acidic_job/base"
require_relative "acidic_job/active_kiq"

require_relative "acidic_job/serializers/exception_serializer"
require_relative "acidic_job/serializers/finished_point_serializer"
require_relative "acidic_job/serializers/job_serializer"
require_relative "acidic_job/serializers/range_serializer"
require_relative "acidic_job/serializers/recovery_point_serializer"
require_relative "acidic_job/serializers/worker_serializer"
require "active_job/serializers"

module AcidicJob
  ::ActiveJob::Serializers.add_serializers(
    Serializers::ExceptionSerializer,
    Serializers::FinishedPointSerializer,
    Serializers::JobSerializer,
    Serializers::RangeSerializer,
    Serializers::RecoveryPointSerializer,
    Serializers::WorkerSerializer
  )
end
