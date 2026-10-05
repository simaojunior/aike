defmodule BiometricsWeb.Router do
  use BiometricsWeb, :router

  pipeline :biometrics_write do
    plug(BiometricsWeb.ServiceAccountAuth, scopes: ["biometrics:write"])
  end

  pipeline :biometrics_read do
    plug(BiometricsWeb.ServiceAccountAuth, scopes: ["biometrics:read"])
  end

  scope "/v1" do
    pipe_through(:biometrics_write)
    post("/facematch", BiometricsWeb.FacematchController, :create)
  end

  scope "/v1" do
    pipe_through(:biometrics_read)
    get("/facematch/:id", BiometricsWeb.FacematchController, :show)
  end
end
