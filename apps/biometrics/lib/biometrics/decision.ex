defmodule Biometrics.Decision do
  @moduledoc """
  Turns a face similarity into a facematch decision with three bands.

  - `approved`: similarity at or above `approve_at`
  - `manual_review`: at or above `review_at`, below `approve_at`; the faces probably
    match, but a person should confirm
  - `rejected`: below `review_at`, or no similarity because a face was missing

  `matched` is true for the first two bands. The limits depend on the model and must be
  measured on authorized selfie and document pairs before production use.

  ## Configuration

      config :biometrics, decision: [approve_at: 0.5, review_at: 0.363]

  ## Examples

      %{matched: true, decision: "manual_review"} = Biometrics.Decision.decide(0.41)
  """

  @doc """
  Decides a facematch.

  ## Parameters
    - similarity: cosine similarity from 0 to 1, or `nil` when no comparison ran

  ## Returns
    - `%{matched: boolean, decision: "approved" | "manual_review" | "rejected"}`
  """
  @spec decide(number() | nil) :: %{matched: boolean(), decision: String.t()}
  def decide(nil), do: %{matched: false, decision: "rejected"}

  def decide(similarity) do
    limits = Application.get_env(:biometrics, :decision, approve_at: 0.5, review_at: 0.363)
    band(similarity, limits[:approve_at], limits[:review_at])
  end

  defp band(similarity, approve_at, _review_at) when similarity >= approve_at,
    do: %{matched: true, decision: "approved"}

  defp band(similarity, _approve_at, review_at) when similarity >= review_at,
    do: %{matched: true, decision: "manual_review"}

  defp band(_similarity, _approve_at, _review_at), do: %{matched: false, decision: "rejected"}
end
