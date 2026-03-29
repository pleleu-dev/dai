defmodule Dai.Repo do
  use Ecto.Repo,
    otp_app: :dai,
    adapter: Ecto.Adapters.Postgres
end
