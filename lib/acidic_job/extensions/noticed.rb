module AcidicJob
	module Extensions
		module Noticed
			extend ActiveSupport::Concern
	
			def deliver_acidicly(recipients)
				# THIS IS A HACK THAT COPIES AND PASTES KEY PARTS OF THE `Noticed::Base` CODE IN ORDER TO ALLOW US TO TRANSACTIONALLY DELIVER NOTIFICATIONS
				# THIS IS THUS LIABLE TO BREAK WHENEVER THAT GEM IS UPDATED
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
						serialized_job = job_class.send(:job_or_instantiate, args).serialize

						AcidicJob::Run.create!(
							staged: true,
							job_class: job_class.name,
							serialized_job: serialized_job, 
							idempotency_key: IdempotencyKey.value_for(serialized_job),
						)
					end
					alias_method :perform_transactionally, :perform_acidicly
				end
			end
		end
	end
end
