project_id = "compraflow"

[api]
enabled = true
port = 54321
schemas = ["public", "graphql_public", "app"]
extra_search_path = ["public", "extensions"]
max_rows = 1000

[db]
port = 54322
major_version = 15

[studio]
enabled = true
port = 54323

[auth]
enabled = true
site_url = "http://127.0.0.1:3000"
additional_redirect_urls = ["http://127.0.0.1:3000"]

[auth.email]
enable_signup = true
enable_confirmations = false
