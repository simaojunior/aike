defmodule AikeVision.FaceTest do
  use ExUnit.Case, async: false
  alias AikeVision.Face

  defp blank_card do
    Nx.broadcast(Nx.tensor(235, type: :u8), {480, 640, 3}) |> Evision.Mat.from_nx_2d()
  end

  @tag :face_models
  test "finds no face on an image without a person" do
    assert Face.detect(blank_card()) == {:ok, []}
  end

  test "without the model files, face detection is unavailable" do
    original = Application.get_env(:aike_vision, :face_models_dir)
    Application.put_env(:aike_vision, :face_models_dir, "/nonexistent/konoha-models")

    try do
      refute Face.available?()
      assert Face.detect(blank_card()) == {:error, :face_models_unavailable}
    after
      Application.put_env(:aike_vision, :face_models_dir, original)
    end
  end
end
