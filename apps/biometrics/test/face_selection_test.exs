defmodule Biometrics.FaceSelectionTest do
  use ExUnit.Case, async: true
  alias Biometrics.FaceSelection

  defp face(left, top, width, height, score),
    do: %{box: {left, top, width, height}, score: score}

  describe "selfie" do
    test "takes the only face" do
      only = face(300, 200, 400, 480, 0.95)
      assert FaceSelection.pick([only], :selfie) == {:ok, only}
    end

    test "refuses no face, a second clear face and a face too small to compare" do
      assert FaceSelection.pick([], :selfie) == {:error, :no_face}

      assert FaceSelection.pick(
               [face(100, 100, 300, 360, 0.95), face(600, 120, 200, 240, 0.9)],
               :selfie
             ) == {:error, :multiple_faces}

      assert FaceSelection.pick([face(10, 10, 30, 36, 0.9)], :selfie) ==
               {:error, :face_too_small}
    end

    test "ignores a small or weak face in the background" do
      main = face(100, 100, 300, 360, 0.95)

      assert FaceSelection.pick([main, face(700, 50, 40, 48, 0.92)], :selfie) == {:ok, main}
      assert FaceSelection.pick([main, face(600, 120, 250, 300, 0.62)], :selfie) == {:ok, main}
    end
  end

  describe "document" do
    test "takes the strongest, largest face; a document may print a second small photo" do
      photo = face(120, 160, 66, 84, 0.94)
      ghost = face(400, 300, 42, 50, 0.7)
      assert FaceSelection.pick([ghost, photo], :document) == {:ok, photo}
    end

    test "refuses no face and a face too small to compare" do
      assert FaceSelection.pick([], :document) == {:error, :no_face}
      assert FaceSelection.pick([face(5, 5, 20, 24, 0.9)], :document) == {:error, :face_too_small}
    end
  end

  test "the bounding box is returned as proportions of the image" do
    assert FaceSelection.bounding_box(face(160, 120, 320, 240, 0.9), {640, 480}) ==
             %{top: 0.25, left: 0.25, width: 0.5, height: 0.5}
  end
end
