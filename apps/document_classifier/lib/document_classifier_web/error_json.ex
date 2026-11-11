defmodule DocumentClassifierWeb.ErrorJSON do
  @moduledoc "Safe problem response for unexpected failures and framework errors."
  def render("400.json", %{reason: %Plug.Parsers.ParseError{}}),
    do: AikeHttp.Problem.body("invalid_json")

  def render(template, _assigns), do: AikeHttp.Problem.from_template(template)
end
