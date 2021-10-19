# frozen_string_literal: true

class SendRideReceiptWorker
  include Sidekiq::Worker
  include AcidicJob

  def perform(amount:, currency:, user_id:)
    # no op
  end
end

class RideCreateWorker
  include Sidekiq::Worker
  include AcidicJob

  class SimulatedTestingFailure < StandardError; end

  def perform(user, ride_params)
    idempotently with: { user: user, params: ride_params, ride: nil } do
      step :create_ride_and_audit_record
      step :create_stripe_charge
      step :send_receipt
    end
  end

  private

  # rubocop:disable Metrics/MethodLength
  def create_ride_and_audit_record
    self.ride = Ride.create!(
      origin_lat: params["origin_lat"],
      origin_lon: params["origin_lon"],
      target_lat: params["target_lat"],
      target_lon: params["target_lon"],
      stripe_charge_id: nil, # no charge created yet
      user: user
    )

    raise SimulatedTestingFailure if defined?(error_in_create_ride) && error_in_create_ride

    # in the same transaction insert an audit record for what happened
    Audit.create!(
      action: :AUDIT_RIDE_CREATED,
      auditable: ride,
      user: user,
      audited_changes: params
    )
  end
  # rubocop:enable Metrics/MethodLength

  # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
  def create_stripe_charge
    raise SimulatedTestingFailure if defined?(error_in_create_stripe_charge) && error_in_create_stripe_charge

    begin
      charge = Stripe::Charge.create({
                                       amount: 20_00,
                                       currency: "usd",
                                       customer: user.stripe_customer_id,
                                       description: "Charge for ride #{ride.id}"
                                     }, {
                                       # Pass through our own unique ID rather than the value
                                       # transmitted to us so that we can guarantee uniqueness to Stripe
                                       # across all Rocket Rides accounts.
                                       idempotency_key: "rocket-rides-atomic-#{key.id}"
                                     })
    rescue Stripe::CardError
      # Short circuits execution by sending execution right to 'finished'.
      # So, ends the job "successfully"
      safely_finish_acidic_job
    else
      # if there is some sort of failure here (like server downtime), what happens?
      ride.update_column(:stripe_charge_id, charge.id)
    end
  end
  # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

  def send_receipt
    # Send a receipt asynchronously by adding an entry to the staged_jobs
    # table. By funneling the job through Postgres, we make this
    # operation transaction-safe.
    SendRideReceiptWorker.perform_transactionally(
      amount: 20_00,
      currency: "usd",
      user_id: user.id
    )
  end
end
