module AcidicJob
	module NotifyTransactionallyExtension
		extend ActiveSupport::Concern

		def deliver_transactionally(recipients)
			# THIS IS A HACK THAT COPIES AND PASTES KEY PARTS OF THE `Noticed::Base` CODE IN ORDER TO ALLOW US TO TRANSACTIONALLY DELIVER NOTIFICATIONS
			# THIS IS THUS LIABLE TO BREAK WHENEVER THAT GEM IS UPDATED

			job_parent_class = Noticed.parent_class.constantize
			job_adapter = if job_parent_class < ActiveJob::Base
				"activejob"
			elsif job_parent_class.include?(Sidekiq::Worker)
				"sidekiq"
			else
				raise UnknownJobAdapter
			end
			delivery_methods = self.class.delivery_methods.dup

			Array.wrap(recipients).uniq.flat_map do |recipient|
				if (index = delivery_methods.find_index { |m| m[:name] == :database })
					delivery_method = delivery_methods.delete_at(index)
					self.record = run_delivery_method(delivery_method, recipient: recipient, enqueue: false, record: nil)
				end

				delivery_methods.map do |delivery_method|
					job_class = delivery_method_for(delivery_method[:name], delivery_method[:options])
					args = {
						notification_class: self.class.name,
						options: delivery_method[:options],
						params: params,
						recipient: recipient,
						record: record
					}
					job_args = job_class.send(:job_or_instantiate, args).serialize
					attributes = {
						adapter: job_adapter,
						job_name: job_class.name,
						job_args: job_args
					}

					AcidicJob::Staged.create!(attributes)
				end
			end
		end
	end
end