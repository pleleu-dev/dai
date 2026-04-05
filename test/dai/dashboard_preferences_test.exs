defmodule Dai.DashboardPreferencesTest do
  use Dai.DataCase, async: true

  alias Dai.DashboardPreferences

  describe "get_preferences/1" do
    test "returns defaults when no preferences saved" do
      prefs = DashboardPreferences.get_preferences("user-1")
      assert prefs.panel_sizes == %{"main_split" => 75, "right_split" => 50}
    end
  end

  describe "save_panel_sizes/2" do
    test "saves and retrieves panel sizes" do
      {:ok, _} =
        DashboardPreferences.save_panel_sizes("user-1", %{
          "main_split" => 60,
          "right_split" => 40
        })

      prefs = DashboardPreferences.get_preferences("user-1")
      assert prefs.panel_sizes == %{"main_split" => 60, "right_split" => 40}
    end

    test "upserts existing preferences" do
      {:ok, _} =
        DashboardPreferences.save_panel_sizes("user-1", %{
          "main_split" => 60,
          "right_split" => 40
        })

      {:ok, _} =
        DashboardPreferences.save_panel_sizes("user-1", %{
          "main_split" => 80,
          "right_split" => 30
        })

      prefs = DashboardPreferences.get_preferences("user-1")
      assert prefs.panel_sizes == %{"main_split" => 80, "right_split" => 30}
    end
  end
end
