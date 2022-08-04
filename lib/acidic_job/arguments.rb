# frozen_string_literal: true

require "active_job/arguments"

module AcidicJob
  module Arguments
    include ActiveJob::Arguments
    extend self # rubocop:disable Style/ModuleFunction

    # `ActiveJob` will throw an error if it tries to deserialize a GlobalID record.
    # However, this isn't the behavior that we want for our custom `ActiveRecord` serializer.
    # Since `ActiveRecord` does _not_ reset instance record state to its pre-transactional state
    # on a transaction ROLLBACK, we can have GlobalID entries in a serialized column that point to
    # non-persisted records. This is ok. We should simply return `nil` for that portion of the
    # serialized field.
    def deserialize_global_id(hash)
      GlobalID::Locator.locate hash[GLOBALID_KEY]
    rescue ActiveRecord::RecordNotFound
      nil
    end
  end
end
