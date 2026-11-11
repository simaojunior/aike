defmodule Biometrics.FaceSelection do
  @moduledoc """
  Chooses the face to compare in each image, by the role of the image.

  - Selfie: exactly one person. A second face counts when it is clear (score at least
    0.8) and at least a quarter of the main face's area; a small or weak face in the
    background is ignored
  - Document: the face with the highest score × area. Some documents print a second,
    smaller photo, so more faces are allowed
  - Both: a face narrower than 40 pixels has too little detail to compare

  ## Properties
    - A face is `%{box: {left, top, width, height}, score: float}` in pixels

  ## Errors
    - `:no_face`, `:multiple_faces` (selfie only), `:face_too_small`

  ## Examples

      {:ok, face} = Biometrics.FaceSelection.pick(faces, :selfie)
  """

  @min_width 40
  @second_face_score 0.8
  @second_face_area 0.25

  @type face :: %{box: {number(), number(), number(), number()}, score: float()}

  @doc """
  Picks the face of an image.

  ## Parameters
    - faces: the detected faces
    - role: `:selfie` or `:document`

  ## Returns
    - `{:ok, face}` or `{:error, :no_face | :multiple_faces | :face_too_small}`
  """
  @spec pick([face()], :selfie | :document) :: {:ok, face()} | {:error, atom()}
  def pick([], _role), do: {:error, :no_face}

  def pick(faces, :selfie) do
    [main | others] = Enum.sort_by(faces, &area/1, :desc)

    if Enum.any?(others, &second_person?(&1, main)),
      do: {:error, :multiple_faces},
      else: large_enough(main)
  end

  def pick(faces, :document), do: faces |> Enum.max_by(&(&1.score * area(&1))) |> large_enough()

  defp second_person?(face, main),
    do: face.score >= @second_face_score and area(face) >= area(main) * @second_face_area

  defp large_enough(%{box: {_, _, width, _}}) when width < @min_width,
    do: {:error, :face_too_small}

  defp large_enough(face), do: {:ok, face}

  defp area(%{box: {_, _, width, height}}), do: width * height

  @doc """
  The face box as proportions of the image, as the API returns it.

  ## Parameters
    - face: the face
    - size: `{width, height}` of the image

  ## Returns
    - `%{top, left, width, height}`, each from 0 to 1 with four decimals
  """
  @spec bounding_box(face(), {pos_integer(), pos_integer()}) :: %{atom() => float()}
  def bounding_box(%{box: {left, top, width, height}}, {image_width, image_height}) do
    %{
      top: ratio(top, image_height),
      left: ratio(left, image_width),
      width: ratio(width, image_width),
      height: ratio(height, image_height)
    }
  end

  defp ratio(value, total), do: Float.round(min(max(value / total, 0.0), 1.0), 4)
end
