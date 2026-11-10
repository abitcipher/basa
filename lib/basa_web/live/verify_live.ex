defmodule BasaWeb.VerifyLive do
  use BasaWeb, :live_view

  alias Basa.Witness.Disclosure

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: gettext("Check a document"), result: nil)
     |> allow_upload(:package,
       accept: ~w(.json),
       max_entries: 1,
       max_file_size: 60_000_000,
       auto_upload: true,
       progress: &handle_progress/3
     )}
  end

  defp handle_progress(:package, entry, socket) when entry.done? do
    result =
      consume_uploaded_entry(socket, entry, fn %{path: path} ->
        {:ok, path |> File.read!() |> Disclosure.check_json()}
      end)

    {:noreply, assign(socket, result: result)}
  end

  defp handle_progress(_, _, socket), do: {:noreply, socket}

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  defp name({:file, i}), do: gettext("File %{n}", n: i + 1)
  defp name({:signature, "offeror"}), do: gettext("Signature of the offeror (lessor or seller)")
  defp name({:signature, "acceptor"}), do: gettext("Signature of the acceptor (lessee or buyer)")
  defp name(:basa_hash), do: gettext("The manifest matches its BASA-HASH")
  defp name(:timestamp), do: gettext("Independent timestamp")

  defp name({:qualified, "offeror"}),
    do: gettext("Qualified signature of the offeror (lessor or seller)")

  defp name({:qualified, "acceptor"}),
    do: gettext("Qualified signature of the acceptor (lessee or buyer)")

  defp name({:qualified, _}), do: gettext("Qualified signature")

  defp name(:in_person),
    do: gettext("Both parties confirmed it in person in MEM (their phones swapped fresh codes)")

  defp name(:package), do: gettext("Package")
  defp name(other), do: inspect(other)

  defp reason(:missing), do: gettext("not included")
  defp reason(:test), do: gettext("test signature, not qualified")

  defp reason({:error, :unknown_issuer}),
    do: gettext("the certificate is not from a trusted provider")

  defp reason({:error, :content_differs}), do: gettext("the file was changed")
  defp reason({:error, :bad_proof}), do: gettext("the file is not part of this contract")
  defp reason({:error, :bad_signature}), do: gettext("the signature does not match")
  defp reason({:error, :mismatch}), do: gettext("does not match")
  defp reason({:error, :not_json}), do: gettext("this is not a BASA package")
  defp reason({:error, :unknown_format}), do: gettext("this is not a BASA package")
  defp reason({:error, other}), do: inspect(other)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} unread={@unread_count}>
      <.page_title title={gettext("Check a document")} info_id="verify-info">
        <:info>
          {gettext(
            "A party to a BASA contract can give you a file together with its proof. Upload that package here: it shows whether the file is exactly the one sealed in the contract, who signed it and when. The package is checked here and not stored."
          )}
        </:info>
      </.page_title>

      <form id="verify-form" phx-change="validate" phx-submit="validate">
        <label class="flex cursor-pointer flex-col items-center gap-2 rounded-2xl border-2 border-dashed border-zinc-300 p-8 text-center hover:bg-zinc-50 dark:border-zinc-700 dark:hover:bg-zinc-900">
          <.icon name="hero-document-check" class="size-8 opacity-60" />
          <span class="font-medium">{gettext("Choose the package (.json)")}</span>
          <.live_file_input upload={@uploads.package} class="hidden" />
        </label>
      </form>

      <.card :if={@result} id="verify-result" padding="medium" rounded="large" class="mt-4">
        <p class={[
          "mb-1 text-lg font-semibold",
          if(@result.ok?,
            do: "text-success-light dark:text-success-dark",
            else: "text-danger-light dark:text-danger-dark"
          )
        ]}>
          {if @result.ok?,
            do: gettext("Authentic: every check passed."),
            else: gettext("Not proven: see below.")}
        </p>
        <p :if={@result[:basa_hash]} class="mb-1 font-mono text-xs break-all opacity-80">
          {@result.basa_hash}
        </p>
        <p :if={@result[:time]} class="mb-3 text-sm">
          {gettext("Sealed no later than %{time} UTC (timestamp authority).",
            time: Calendar.strftime(@result.time, "%d.%m.%Y %H:%M")
          )}
        </p>
        <ul class="space-y-1 text-sm">
          <li :for={{check, r} <- @result.checks} class="flex items-center gap-2">
            <.icon
              name={
                case r do
                  :ok -> "hero-check-circle-solid"
                  :missing -> "hero-minus-circle"
                  :test -> "hero-beaker"
                  _ -> "hero-x-circle-solid"
                end
              }
              class={[
                "size-4",
                r == :ok && "text-success-light dark:text-success-dark",
                r in [:missing, :test] && "opacity-50",
                match?({:error, _}, r) && "text-danger-light dark:text-danger-dark"
              ]}
            />
            {name(check)}
            <span :if={r != :ok} class="text-xs opacity-70">· {reason(r)}</span>
          </li>
        </ul>
      </.card>
    </Layouts.app>
    """
  end
end
