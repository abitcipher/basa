defmodule Basa.Bookings do
  use Ash.Domain, otp_app: :basa, extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource Basa.Bookings.Booking do
      rpc_action(:lessor_schedule, :schedule)
      rpc_action(:lessor_timeline, :timeline)
      rpc_action(:lessor_stats, :stats)
      rpc_action(:admin_bookings, :admin_list)
    end
  end

  resources do
    resource Basa.Bookings.Booking do
      define :book, action: :book
      define :confirm_booking, action: :confirm
      define :decline_booking, action: :decline
      define :cancel_booking, action: :cancel
      define :complete_booking, action: :complete
      define :list_my_bookings, action: :mine
      define :list_incoming_bookings, action: :incoming
      define :get_booking, action: :read, get_by: [:id]
      define :lessor_schedule, action: :schedule, args: [:from, :to]
      define :lessor_timeline, action: :timeline, args: [:from, :to]
      define :lessor_stats, action: :stats, args: [:from, :to]
    end

    resource Basa.Bookings.Claim
  end
end
