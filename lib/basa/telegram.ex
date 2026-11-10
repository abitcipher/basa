defmodule Basa.Telegram do
  require Logger

  def token, do: Application.get_env(:basa, :telegram)[:bot_token]
  def username, do: Application.get_env(:basa, :telegram)[:bot_username]
  def configured?, do: token() not in [nil, ""]

  def enabled?, do: configured?() and Basa.Services.on?(:telegram)

  def download(file_id) do
    if emulator?() do
      BasaTma.Emulator.file(file_id)
    else
      with {:ok, file} <- ExGram.get_file(file_id, token: token()),
           {:ok, %{status: 200, body: body}} <-
             Req.get(ExGram.File.file_url(file, token: token()), decode_body: false) do
        {:ok, body, "image/jpeg"}
      end
    end
  end

  def emulator?, do: Application.get_env(:basa, :telegram, [])[:updates] == :emulator

  def emulator_options do
    [
      pubsub: Basa.PubSub,
      bot: :basa_bot,
      title: "BASA",
      icon: "/images/icon-512.png",
      menu_path: "/tg?to=%2Fapp",
      file_path: "/dev/telegram/file/",
      commands: ["/start", "/search Odesa", "/search studio", "/bookings", "/add"]
    ]
  end

  def verify_init_data(init_data), do: BasaTma.Auth.verify_init_data(init_data, token())
  def verify_login_widget(fields), do: BasaTma.Auth.verify_login_widget(fields, token())

  def user_attrs(telegram_user) do
    {code, attrs} = telegram_user |> BasaTma.Auth.user_attrs() |> Map.pop(:language_code)

    locale =
      case Basa.I18n.supported(code) do
        nil -> :en
        code -> String.to_existing_atom(code)
      end

    Map.put(attrs, :locale, locale)
  end

  def send_message(chat_id, text, opts \\ []) do
    if enabled?() do
      ExGram.send_message(chat_id, text, Keyword.put(opts, :token, token()))
    else
      Logger.debug("telegram disabled, skipped message to #{chat_id}: #{text}")
      {:ok, :skipped}
    end
  end
end
