defmodule Biometrics.Engine.OpenCV do
  @moduledoc """
  Local facematch engine: OpenCV YuNet finds the faces and SFace compares them
  (`AikeVision.Face`). No external service receives the images.

  Each file may be a JPEG, a PNG or a single-page PDF. In a PDF, the embedded images are
  searched first (a digital CNH keeps the photo there), then the rendered page; the first
  image with a face is used. When no face is found, the image is tried in the other three
  rotations, so a document photographed sideways or a selfie with lost EXIF orientation
  still works. Images are reduced to 1280 pixels on the longest side before detection.

  The face of each file is chosen by `Biometrics.FaceSelection`. The comparison runs only
  when both files have a usable face; otherwise the result has no similarity and lists
  the problem of each file. The decision bands are in `Biometrics.Decision`.

  ## Configuration

      config :biometrics,
        engine: Biometrics.Engine.OpenCV,
        engine_version: "opencv-yunet2023mar-sface2021dec-1"

  ## Errors
    - `:invalid_image`: a file is not a supported image or single-page PDF
    - `:face_models_unavailable`: the model files are missing
    - `:face_detection_failed`, `:timeout`

  ## Examples

      {:ok, %{"similarity_score" => 0.71, "resources" => [_, _]}} =
        Biometrics.Engine.OpenCV.compare(selfie_bytes, document_bytes, [])
  """
  @behaviour Biometrics.Engine

  alias AikeVision.{Face, Image, Pdf, Workspace}
  alias Biometrics.{Decision, FaceSelection}

  @version "opencv-yunet2023mar-sface2021dec-1"
  @max_side 1280
  @timeout_ms 30_000
  @invalid [:unsupported_image, :image_too_large, :unsupported_page_count, :command_failed]

  @doc """
  The engine version this module implements.

  ## Returns
    - the version string
  """
  @spec version() :: String.t()
  def version, do: @version

  @impl true
  def compare(selfie, document, _opts) do
    case Workspace.run(&compare_in(selfie, document, &1), @timeout_ms) do
      {:error, reason} when reason in @invalid -> {:error, :invalid_image}
      result -> result
    end
  end

  defp compare_in(selfie, document, directory) do
    with {:ok, selfie_candidates} <- candidates(selfie, directory, "selfie"),
         {:ok, document_candidates} <- candidates(document, directory, "document"),
         {:ok, selfie_found} <- find(selfie_candidates, :selfie),
         {:ok, document_found} <- find(document_candidates, :document) do
      result(selfie_found, document_found)
    end
  end

  defp candidates(<<"%PDF-", _::binary>> = bytes, directory, name) do
    path = Path.join(directory, name <> ".pdf")

    with :ok <- File.write(path, bytes),
         :ok <- Pdf.single_page(path),
         {:ok, embedded} <- Pdf.embedded_images(path, directory),
         {:ok, page} <- Pdf.render_page(path, directory, 2000) do
      {:ok, Enum.map(embedded ++ [page], &{:path, &1})}
    end
  end

  defp candidates(bytes, _directory, _name) do
    with {:ok, image, _header} <- Image.decode(bytes), do: {:ok, [{:image, image}]}
  end

  defp find(candidates, role) do
    Enum.reduce_while(candidates, {:ok, %{image: nil, faces: []}}, fn candidate, acc ->
      case faces_in(candidate) do
        {:ok, %{faces: [_ | _]} = found} -> {:halt, {:ok, found}}
        {:ok, _none} -> {:cont, acc}
        error -> {:halt, error}
      end
    end)
    |> with_role(role)
  end

  defp with_role({:ok, found}, role), do: {:ok, Map.put(found, :role, role)}
  defp with_role(error, _role), do: error

  defp faces_in({:path, path}) do
    case Image.read(path) do
      {:ok, image, _header} -> faces_in({:image, image})
      _ -> {:ok, %{image: nil, faces: []}}
    end
  end

  defp faces_in({:image, image}) do
    image = Image.shrink(image, @max_side)

    Enum.reduce_while(Image.rotations(), {:ok, %{image: image, faces: []}}, fn rotation, acc ->
      rotated = Image.rotate(image, rotation)

      case Face.detect(rotated) do
        {:ok, [_ | _] = faces} -> {:halt, {:ok, %{image: rotated, faces: faces}}}
        {:ok, []} -> {:cont, acc}
        error -> {:halt, error}
      end
    end)
  end

  defp result(selfie, document) do
    with {:ok, comparison} <- comparison(selfie, document) do
      {:ok,
       Map.merge(comparison, %{
         "selfie_face_detected" => selfie.faces != [],
         "document_face_detected" => document.faces != [],
         "faces" => %{
           "selfie_image" => length(selfie.faces),
           "document_image" => length(document.faces)
         }
       })}
    end
  end

  defp comparison(selfie, document) do
    case {FaceSelection.pick(selfie.faces, :selfie),
          FaceSelection.pick(document.faces, :document)} do
      {{:ok, selfie_face}, {:ok, document_face}} ->
        compared(selfie, selfie_face, document, document_face)

      picks ->
        {:ok, not_compared(picks)}
    end
  end

  defp compared(selfie, selfie_face, document, document_face) do
    with {:ok, selfie_features} <- Face.features(selfie.image, selfie_face),
         {:ok, document_features} <- Face.features(document.image, document_face) do
      similarity = Float.round(Face.similarity(selfie_features, document_features), 4)

      {:ok,
       %{
         "match" => Decision.decide(similarity).matched,
         "similarity_score" => similarity,
         "resources" => [
           resource("selfie_image", selfie.image, selfie_face),
           resource("document_image", document.image, document_face)
         ],
         "issues" => %{"selfie_image" => [], "document_image" => []}
       }}
    end
  end

  defp not_compared({selfie_pick, document_pick}) do
    %{
      "match" => false,
      "similarity_score" => nil,
      "resources" => [],
      "issues" => %{
        "selfie_image" => issues(selfie_pick),
        "document_image" => issues(document_pick)
      }
    }
  end

  defp issues({:ok, _face}), do: []
  defp issues({:error, issue}), do: [Atom.to_string(issue)]

  defp resource(fieldname, image, face) do
    box = FaceSelection.bounding_box(face, Image.size(image))

    %{
      "fieldname" => fieldname,
      "page" => 0,
      "face" => %{
        "confidence" => Float.round(face.score, 4),
        "bounding_box" => Map.new(box, fn {key, value} -> {Atom.to_string(key), value} end)
      }
    }
  end
end
