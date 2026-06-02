defmodule Dai.RateLimiterTest do
  use ExUnit.Case, async: true

  alias Dai.RateLimiter

  @config %{limit: 3, window_ms: 60_000}

  describe "new/2" do
    test "starts with a full bucket" do
      bucket = RateLimiter.new(@config, 0)
      assert bucket.tokens == 3.0
      assert bucket.last_refill == 0
    end
  end

  describe "take/2" do
    test "spends one token per call at the same instant" do
      bucket = RateLimiter.new(@config, 1_000)

      assert {:ok, bucket} = RateLimiter.take(bucket, 1_000)
      assert {:ok, bucket} = RateLimiter.take(bucket, 1_000)
      assert {:ok, bucket} = RateLimiter.take(bucket, 1_000)
      assert {:rate_limited, _bucket} = RateLimiter.take(bucket, 1_000)
    end

    test "refills proportionally to elapsed time" do
      bucket = RateLimiter.new(@config, 0)

      # Drain the bucket at t=0.
      {:ok, bucket} = RateLimiter.take(bucket, 0)
      {:ok, bucket} = RateLimiter.take(bucket, 0)
      {:ok, bucket} = RateLimiter.take(bucket, 0)
      assert {:rate_limited, bucket} = RateLimiter.take(bucket, 0)

      # One full window later, the bucket has refilled to capacity.
      assert {:ok, bucket} = RateLimiter.take(bucket, 60_000)
      # A third of a window refills exactly one token (limit 3 / window).
      assert {:ok, _bucket} = RateLimiter.take(bucket, 80_000)
    end

    test "never refills beyond the limit" do
      bucket = RateLimiter.new(@config, 0)
      {:ok, bucket} = RateLimiter.take(bucket, 0)

      # A huge elapsed time still caps tokens at `limit`, so only `limit` calls pass.
      assert {:ok, bucket} = RateLimiter.take(bucket, 10_000_000)
      assert {:ok, bucket} = RateLimiter.take(bucket, 10_000_000)
      assert {:ok, bucket} = RateLimiter.take(bucket, 10_000_000)
      assert {:rate_limited, _bucket} = RateLimiter.take(bucket, 10_000_000)
    end

    test "carries the updated refill timestamp even when rate limited" do
      bucket = RateLimiter.new(%{limit: 1, window_ms: 1_000}, 0)
      {:ok, bucket} = RateLimiter.take(bucket, 0)

      assert {:rate_limited, bucket} = RateLimiter.take(bucket, 100)
      assert bucket.last_refill == 100
    end
  end
end
