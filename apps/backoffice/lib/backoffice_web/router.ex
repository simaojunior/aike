defmodule BackofficeWeb.Router do
  use Phoenix.Router

  scope "/v1" do
    post("/auth/bootstrap", BackofficeWeb.AuthController, :bootstrap)
    post("/auth/login", BackofficeWeb.AuthController, :login)
    post("/auth/refresh", BackofficeWeb.AuthController, :refresh)
    post("/auth/logout", BackofficeWeb.AuthController, :logout)
    post("/auth/logout-all", BackofficeWeb.AuthController, :logout_all)
    post("/auth/password", BackofficeWeb.AuthController, :password)
    get("/auth/me", BackofficeWeb.AuthController, :me)
    get("/users", BackofficeWeb.UserController, :index)
    post("/users", BackofficeWeb.UserController, :create)
    patch("/users/:id", BackofficeWeb.UserController, :update)
    post("/companies", BackofficeWeb.ProvisioningController, :create_company)
    post("/service-accounts", BackofficeWeb.ProvisioningController, :create_service_account)
  end
end
