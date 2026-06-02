defmodule Dai.RateLimiter do
  @moduledoc """
  Monotonic-time token bucket for per-socket query throttling.

  The bucket refills continuously at `limit` tokens per `window_ms`; each accepted
  query spends one token. The current time (`now`, in milliseconds) is passed in
  rather than read internally, so the refill behavior is deterministically testable
  and the struct stays free of side effects.
  """

  @enforce_keys [:tokens, :last_refill, :limit, :window_ms]
  defstruct [:tokens, :last_refill, :limit, :window_ms]

  @type t :: %__MODULE__{
          tokens: float(),
          last_refill: integer(),
          limit: pos_integer(),
          window_ms: pos_integer()
        }

  @doc "Builds a full bucket from a `%{limit:, window_ms:}` config and the current time."
  @spec new(%{limit: pos_integer(), window_ms: pos_integer()}, integer()) :: t()
  def new(%{limit: limit, window_ms: window_ms}, now) do
    %__MODULE__{tokens: limit * 1.0, last_refill: now, limit: limit, window_ms: window_ms}
  end

  @doc """
  Refills by the time elapsed since `last_refill`, then spends one token.

  Returns `{:ok, bucket}` when a token was available, or `{:rate_limited, bucket}`
  when the bucket is empty. Either way the returned bucket carries the updated
  refill timestamp, so elapsed time is never lost.
  """
  @spec take(t(), integer()) :: {:ok, t()} | {:rate_limited, t()}
  def take(%__MODULE__{} = bucket, now) do
    elapsed = now - bucket.last_refill
    refilled = min(bucket.limit * 1.0, bucket.tokens + elapsed * bucket.limit / bucket.window_ms)

    if refilled >= 1.0 do
      {:ok, %{bucket | tokens: refilled - 1.0, last_refill: now}}
    else
      {:rate_limited, %{bucket | tokens: refilled, last_refill: now}}
    end
  end
end
