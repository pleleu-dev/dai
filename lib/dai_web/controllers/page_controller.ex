defmodule DaiWeb.PageController do
  use DaiWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
