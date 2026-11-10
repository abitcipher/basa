render_image? =
  System.find_executable("docker") != nil and
    match?(
      {_, 0},
      System.cmd("docker", ~w(image inspect --format . basa/render:0.1), stderr_to_stdout: true)
    )

ExUnit.start(exclude: if(render_image?, do: [], else: [:browser]))
Ecto.Adapters.SQL.Sandbox.mode(Basa.Repo, :manual)
