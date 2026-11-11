defmodule BackofficeWeb.Schemas.Params do
  @moduledoc "Peri schemas for public administrative inputs, before any domain or Ecto call."
  import Peri
  alias BackofficeWeb.Schemas.InputRules
  alias KycCore.Auth.Scopes

  @name {:string, [min: 2, max: 160, regex: ~r/\S/u]}
  @email {:string, [max: 254, regex: ~r/\A[^\s@]+@[^\s@]+\.[^\s@]+\z/u]}
  @password {:custom, {InputRules, :new_password}}
  @credential {:custom, {InputRules, :credential}}
  @uuid {:custom, {InputRules, :uuid}}
  @role {:enum, ~w(platform_admin company_admin company_user)}

  defschema(:bootstrap, %{
    "companyName" => {:required, @name},
    "name" => {:required, @name},
    "email" => {:required, @email},
    "password" => {:required, @password}
  })

  defschema(:login, %{"email" => {:required, @email}, "password" => {:required, @credential}})
  defschema(:refresh, %{"refreshToken" => {:required, @credential}})

  defschema(:password, %{
    "currentPassword" => {:required, @credential},
    "newPassword" => {:required, @password}
  })

  defschema(:create_user, %{
    "name" => {:required, @name},
    "email" => {:required, @email},
    "password" => {:required, @password},
    "role" => @role,
    "companyId" => @uuid
  })

  defschema(:update_user, %{
    "id" => {:required, @uuid},
    "role" => @role,
    "active" => :boolean
  })

  defschema(:create_company, %{"name" => {:required, @name}})

  defschema(:create_service_account, %{
    "name" => {:required, @name},
    "companyId" => @uuid,
    "accountId" => {:string, [min: 3, max: 128]},
    "scopes" => {:required, {:list, {:enum, Scopes.all()}}}
  })

  defschema(:introspect, %{
    "accountId" => {:required, {:string, [min: 1, max: 128]}},
    "secret" => {:required, {:string, [min: 1, max: 512]}}
  })
end
