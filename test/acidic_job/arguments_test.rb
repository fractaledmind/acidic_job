# frozen_string_literal: true

require "test_helper"

class AcidicJob::ArgumentsTest < ActiveSupport::TestCase
  # The GlobalID key used by ActiveJob for serialization
  GLOBALID_KEY = "_aj_globalid"

  # ============================================
  # deserialize_global_id
  # ============================================

  test "deserialize_global_id locates existing record" do
    thing = Thing.create!
    gid_hash = { GLOBALID_KEY => thing.to_global_id.to_s }

    result = AcidicJob::Arguments.deserialize_global_id(gid_hash)

    assert_equal thing, result
  end

  test "deserialize_global_id returns nil for deleted record" do
    thing = Thing.create!
    gid_hash = { GLOBALID_KEY => thing.to_global_id.to_s }
    thing.destroy!

    result = AcidicJob::Arguments.deserialize_global_id(gid_hash)

    assert_nil result
  end

  test "deserialize_global_id returns nil for non-existent record ID" do
    # Create a GlobalID for a record that doesn't exist
    gid_hash = { GLOBALID_KEY => "gid://dummy/Thing/999999" }

    result = AcidicJob::Arguments.deserialize_global_id(gid_hash)

    assert_nil result
  end

  # ============================================
  # convert_to_global_id_hash
  # ============================================

  test "convert_to_global_id_hash returns GlobalID hash for persisted record" do
    thing = Thing.create!

    result = AcidicJob::Arguments.convert_to_global_id_hash(thing)

    assert_kind_of Hash, result
    assert result.key?(GLOBALID_KEY)
    assert_match(/gid:\/\/.*\/Thing\/#{thing.id}/, result[GLOBALID_KEY])
  end

  test "convert_to_global_id_hash falls back to ActiveJob serializer for new record" do
    new_thing = Thing.new  # not persisted, no ID

    result = AcidicJob::Arguments.convert_to_global_id_hash(new_thing)

    # Should use ActiveJob::Serializers.serialize which uses our NewRecordSerializer
    assert_kind_of Hash, result
    # The result should have some serialization key (exact key depends on serializer)
    assert result.key?("_aj_serialized") || result.key?(GLOBALID_KEY)
  end
end
