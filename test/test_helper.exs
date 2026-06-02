ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Dai.Repo, :manual)

Mox.defmock(Dai.AI.ClientMock, for: Dai.AI.ClientBehaviour)
