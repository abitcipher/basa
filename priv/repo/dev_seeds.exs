if Mix.env() == :prod, do: raise("dev seeds are not for production")

for {email, name, role} <- [{"lessor@basa.test", "Olena (lessor)", :user}, {"lessee@basa.test", "Max (lessee)", :user}, {"admin@basa.test", "Admin", :admin}] do
  Ash.Seed.upsert!(
    Basa.Accounts.User,
    %{
      email: email,
      display_name: name,
      role: role,
      hashed_password: Bcrypt.hash_pwd_salt("password1234"),
      confirmed_at: DateTime.utc_now()
    },
    identity: :unique_email
  )
end

IO.puts("Dev users ready: lessor@basa.test, lessee@basa.test, admin@basa.test (password1234)")
