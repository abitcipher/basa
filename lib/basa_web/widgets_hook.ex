defmodule BasaWeb.WidgetsHook do
  import Phoenix.Component

  def on_mount(:default, _params, _session, socket),
    do: {:cont, assign(socket, :widgets?, Basa.System.widgets_enabled?())}
end
