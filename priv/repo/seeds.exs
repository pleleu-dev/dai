alias Dai.Repo
alias Dai.Demo.Analytics.{Plan, User, Subscription, Invoice, Event, Feature}

# Fixed seed for reproducibility
:rand.seed(:exsss, {42, 42, 42})

now = DateTime.utc_now() |> DateTime.truncate(:second)

# --- Plans ---
plans =
  [
    %{name: "Free", price_monthly: 0, tier: "free"},
    %{name: "Starter", price_monthly: 2900, tier: "starter"},
    %{name: "Pro", price_monthly: 7900, tier: "pro"},
    %{name: "Enterprise", price_monthly: 19_900, tier: "enterprise"}
  ]
  |> Enum.map(fn attrs ->
    %Plan{}
    |> Plan.changeset(attrs)
    |> Repo.insert!()
  end)

plan_ids = Enum.map(plans, & &1.id)

# --- Features (5 per plan) ---
feature_names = [
  "Dashboard",
  "API Access",
  "Custom Reports",
  "SSO",
  "Audit Log",
  "Webhooks",
  "Priority Support",
  "Data Export",
  "Team Management",
  "Advanced Analytics",
  "White Label",
  "Dedicated Instance",
  "SLA Guarantee",
  "Custom Integrations",
  "Unlimited Storage",
  "Multi-Region",
  "Role-Based Access",
  "Sandbox Environment",
  "Real-Time Alerts",
  "Compliance Pack"
]

for {plan, idx} <- Enum.with_index(plans) do
  count = (idx + 1) * 5

  feature_names
  |> Enum.take(count)
  |> Enum.each(fn name ->
    %Feature{plan_id: plan.id}
    |> Feature.changeset(%{name: name, enabled: true})
    |> Repo.insert!()
  end)
end

# --- Users (200) ---
orgs = ["Acme Corp", "Globex Inc", "Initech", "Umbrella Co", "Stark Industries"]
roles = ["admin", "manager", "member", "member", "member"]

first_names = [
  "Alice",
  "Bob",
  "Carol",
  "Dave",
  "Eve",
  "Frank",
  "Grace",
  "Hank",
  "Iris",
  "Jack",
  "Kate",
  "Leo",
  "Mia",
  "Nick",
  "Olivia",
  "Pete",
  "Quinn",
  "Rose",
  "Sam",
  "Tina"
]

last_names = [
  "Smith",
  "Jones",
  "Brown",
  "Davis",
  "Wilson",
  "Clark",
  "Lewis",
  "Hall",
  "Young",
  "King"
]

users =
  for i <- 1..200 do
    first = Enum.random(first_names)
    last = Enum.random(last_names)
    org = Enum.at(orgs, rem(i - 1, 5))
    days_ago = :rand.uniform(365)
    created = DateTime.add(now, -days_ago * 86_400, :second)

    %User{}
    |> User.changeset(%{
      name: "#{first} #{last}",
      email: "#{String.downcase(first)}.#{String.downcase(last)}.#{i}@example.com",
      role: Enum.random(roles),
      org_name: org
    })
    |> Ecto.Changeset.put_change(:inserted_at, created)
    |> Ecto.Changeset.put_change(:updated_at, created)
    |> Repo.insert!()
  end

# --- Subscriptions (1 per user) ---
subscriptions =
  for user <- users do
    roll = :rand.uniform(100)

    status =
      cond do
        roll <= 70 -> "active"
        roll <= 90 -> "cancelled"
        true -> "past_due"
      end

    plan_id = Enum.random(plan_ids)
    started_days_ago = :rand.uniform(365)
    started = DateTime.add(now, -started_days_ago * 86_400, :second)

    cancelled_at =
      if status == "cancelled" do
        cancel_days = :rand.uniform(started_days_ago)
        DateTime.add(now, -cancel_days * 86_400, :second)
      end

    %Subscription{user_id: user.id, plan_id: plan_id}
    |> Subscription.changeset(%{
      status: status,
      started_at: started,
      cancelled_at: cancelled_at
    })
    |> Repo.insert!()
  end

# --- Invoices (~12 months per subscription) ---
for sub <- subscriptions do
  plan = Enum.find(plans, &(&1.id == sub.plan_id))
  months_active = max(1, div(DateTime.diff(now, sub.started_at, :second), 30 * 86_400))
  months_to_generate = min(months_active, 12)

  for month_offset <- 0..(months_to_generate - 1) do
    due = Date.add(Date.utc_today(), -month_offset * 30)

    variation = plan.price_monthly * (:rand.uniform(21) - 11) / 100
    amount = max(0, plan.price_monthly + trunc(variation))

    invoice_status =
      cond do
        month_offset > 0 -> "paid"
        sub.status == "past_due" -> "pending"
        true -> Enum.random(["paid", "paid", "paid", "pending", "failed"])
      end

    paid_at =
      if invoice_status == "paid" do
        DateTime.add(
          DateTime.new!(due, ~T[09:00:00], "Etc/UTC"),
          :rand.uniform(5) * 86_400,
          :second
        )
      end

    %Invoice{subscription_id: sub.id}
    |> Invoice.changeset(%{
      amount_cents: amount,
      status: invoice_status,
      due_date: due,
      paid_at: paid_at
    })
    |> Repo.insert!()
  end
end

# --- Events (~5000, spread over 90 days) ---
event_names = ["page_view", "signup", "upgrade", "downgrade", "feature_used"]
event_weights = [50, 10, 5, 3, 32]

weighted_events =
  Enum.zip(event_names, event_weights)
  |> Enum.flat_map(fn {name, weight} -> List.duplicate(name, weight) end)

for _i <- 1..5000 do
  user = Enum.random(users)
  event_name = Enum.random(weighted_events)
  days_ago = :rand.uniform(90) - 1
  hour = 8 + :rand.uniform(10)
  minute = :rand.uniform(60) - 1
  event_time = DateTime.add(now, -(days_ago * 86_400) + hour * 3600 + minute * 60, :second)

  properties =
    case event_name do
      "page_view" ->
        %{"page" => Enum.random(["/dashboard", "/settings", "/billing", "/reports", "/home"])}

      "feature_used" ->
        %{"feature" => Enum.random(["Dashboard", "API Access", "Custom Reports", "Data Export"])}

      "upgrade" ->
        %{
          "from_plan" => Enum.random(["free", "starter"]),
          "to_plan" => Enum.random(["starter", "pro"])
        }

      "downgrade" ->
        %{
          "from_plan" => Enum.random(["pro", "enterprise"]),
          "to_plan" => Enum.random(["starter", "free"])
        }

      _ ->
        %{}
    end

  %Event{user_id: user.id}
  |> Event.changeset(%{name: event_name, properties: properties})
  |> Ecto.Changeset.put_change(:inserted_at, event_time)
  |> Repo.insert!()
end

IO.puts(
  "Seeded: #{length(plans)} plans, #{length(users)} users, #{length(subscriptions)} subscriptions, events, invoices, features"
)
