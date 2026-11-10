defmodule Basa.AshTypescriptManifest do
  use AshTypescript.Manifest,
    otp_app: :basa,
    domains: [Basa.Catalog, Basa.Bookings, Basa.Accounts, Basa.Payments]
end
