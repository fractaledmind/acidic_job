# frozen_string_literal: true

require "active_support/concern"

module AcidicJob
  module PerformTransactionallyExtension
    extend ActiveSupport::Concern

    class_methods do
      # rubocop:disable Metrics/MethodLength
      def perform_transactionally(*args)
        attributes = if self < ActiveJob::Base
                       {
                         adapter: "activejob",
                         job_name: name,
                         job_args: job_or_instantiate(*args).serialize
                       }
                     elsif include? Sidekiq::Worker
                       {
                         adapter: "sidekiq",
                         job_name: name,
                         job_args: args
                       }
                     else
                       raise UnknownJobAdapter
                     end

        AcidicJob::Staged.create!(attributes)
      end
      # rubocop:enable Metrics/MethodLength
    end
  end
end
