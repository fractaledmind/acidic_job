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

    # In order to allow our `NewRecordSerializer` a chance to work, we need to ensure that
    # ActiveJob's first attempt to serialize an ActiveRecord model doesn't throw an exception.
    def convert_to_global_id_hash(argument)
      { GLOBALID_KEY => argument.to_global_id.to_s }
    rescue URI::GID::MissingModelIdError
      Serializers.serialize(argument)
    end
  end
end
