# frozen_string_literal: true

require "active_support/concern"

module AcidicJob
	# recreate the original `Key` model
	class Key < ::ActiveRecord::Base
		RECOVERY_POINT_FINISHED = "FINISHED"

		self.table_name = "acidic_job_keys"

		serialize :error_object
		serialize :job_args
		serialize :workflow
		store :attr_accessors
	end

	# recreate the original `Staged` model
	class Staged < ActiveRecord::Base
		self.table_name = "staged_acidic_jobs"
	
		serialize :job_args

		after_create_commit :enqueue_job

		private
	
		# rubocop:disable Metrics/AbcSize, Metrics/MethodLength
		def enqueue_job
			gid = { "staged_job_gid" => to_global_id.to_s }
	
			if job_args.is_a?(Hash) && job_args.key?("arguments")
				job_args["arguments"].concat([gid])
			else
				job_args.concat([gid])
			end
	
			case adapter
			when "activejob"
				::ActiveJob::Base.deserialize(job_args).enqueue
			when "sidekiq"
				job_name.constantize.perform_async(*job_args)
			else
				raise UnknownJobAdapter.new(adapter: adapter)
			end
	
			# NOTE: record will be deleted after the job has successfully been performed
			true
		end
		# rubocop:enable Metrics/AbcSize, Metrics/MethodLength
	end

	module UpgradeService
		def self.execute()
			# prepare an array to hold the attribute hashes to be passed to `insert_all`
			run_attributes = []
			# prepare an array to hold any `Key` records that we couldn't successfully map to `Run` records
			errored_keys = []

			# iterate over all `AcidicJob::Key` records in batches, preparing a `Run` attribute hash to be passed to `insert_all`
			::AcidicJob::Key.find_each do |key|
				# map all of the simple attributes directly
				attributes = {
					id: key.id, 
					staged: false, 
					idempotency_key: key.idempotency_key, 
					job_class: key.job_name, 
					last_run_at: key.last_run_at, 
					locked_at: key.locked_at, 
					recovery_point: key.recovery_point, 
					error_object: key.error_object, 
					attr_accessors: key.attr_accessors, 
					workflow: key.workflow, 
					created_at: key.created_at, 
					updated_at: key.updated_at 
				}

				# prepare the more complicated `job_args` -> `serialized_job` translation
				job_class = key.job_name.constantize
				if defined?(::Sidekiq) && job_class.include?(::Sidekiq::Worker)
					job_class.include(::AcidicJob::Extensions::Sidekiq) unless job_class.include?(::AcidicJob::Extensions::Sidekiq)
					job_instance = job_class.new
					serialized_job = job_instance.serialize_job(*key.job_args)
				elsif defined?(::ActiveJob) && job_class < ::ActiveJob::Base
					job_class.include(::AcidicJob::Extensions::ActiveJob) unless job_class.include?(::AcidicJob::Extensions::ActiveJob)
					job_args = begin
						::ActiveJob::Arguments.deserialize(key.job_args)
					rescue ::ActiveJob::DeserializationError
						key.job_args
					end
					job_instance = job_class.new(*job_args)
					serialized_job = job_instance.serialize_job()
				end

				attributes[:serialized_job] = serialized_job
				run_attributes << attributes
			rescue StandardError => exception
				errored_keys << [exception, key]
			end

			# insert all of the `Run` records
			::AcidicJob::Run.insert_all(run_attributes)

			# delete all successfully migrated `Key` record
			::AcidicJob::Key.where(id: ::AcidicJob::Run.select(:id)).delete_all

			# return a report of the upgrade migration
			{
				run_records: ::AcidicJob::Run.count,
				key_records: ::AcidicJob::Key.count,
				errored_keys: errored_keys
			}
		end
	end
end
