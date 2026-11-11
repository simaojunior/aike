defmodule AikeVision.Face do
  @moduledoc """
  Face detection and comparison with OpenCV models: YuNet finds faces and SFace turns a
  face into a feature vector.

  The models are ONNX files from the OpenCV Zoo (YuNet under MIT, SFace under Apache 2.0),
  downloaded by `scripts/fetch_face_models.sh` and checked by SHA-256. They are not in Git.
  Every call holds a slot of `AikeVision.Processes`, so face work shares the node's CPU
  limit with OCR.

  ## Configuration

      config :aike_vision, face_models_dir: "/app/models"

  ## Properties
    - A face is `%{box: {left, top, width, height}, score: float, landmarks: [float]}`, in
      pixels of the image given to `detect/1`

  ## Errors
    - `:face_models_unavailable`: a model file is missing
    - `:face_detection_failed`: OpenCV could not run the model on the image

  ## Examples

      {:ok, [face | _]} = AikeVision.Face.detect(image)
      {:ok, features} = AikeVision.Face.features(image, face)
      0.91 = AikeVision.Face.similarity(features, other_features)
  """
  alias AikeVision.Limiter

  @detector "face_detection_yunet_2023mar.onnx"
  @recognizer "face_recognition_sface_2021dec.onnx"
  @score_threshold 0.6

  @type face :: %{
          box: {number(), number(), number(), number()},
          score: float(),
          landmarks: [float()]
        }

  @doc """
  The model file names, as `scripts/fetch_face_models.sh` saves them.

  ## Returns
    - the detector and recognizer file names
  """
  @spec model_files() :: [String.t()]
  def model_files, do: [@detector, @recognizer]

  @doc """
  Tells whether both model files are present.

  ## Returns
    - `true` when face detection and comparison can run
  """
  @spec available?() :: boolean()
  def available? do
    case Application.get_env(:aike_vision, :face_models_dir) do
      nil -> false
      directory -> Enum.all?(model_files(), &File.regular?(Path.join(directory, &1)))
    end
  end

  @doc """
  Finds the faces in a BGR image.

  ## Parameters
    - image: a BGR image (`Evision.Mat.t()`)

  ## Returns
    - `{:ok, faces}`, possibly empty, with box, score and the five landmarks
    - `{:error, :face_models_unavailable | :face_detection_failed}`
  """
  @spec detect(Evision.Mat.t()) :: {:ok, [face()]} | {:error, atom()}
  def detect(image) do
    with :ok <- check_models() do
      Limiter.run(AikeVision.Processes, fn -> run_detection(image) end, :infinity)
    end
  end

  defp run_detection(image) do
    {width, height} = AikeVision.Image.size(image)

    detector =
      Evision.FaceDetectorYN.create(model(@detector), "", {width, height},
        score_threshold: @score_threshold
      )

    case Evision.FaceDetectorYN.detect(detector, image) do
      {_, %Evision.Mat{} = rows} -> {:ok, rows |> Evision.Mat.to_nx(Nx.BinaryBackend) |> faces()}
      {_, _} -> {:ok, []}
      _ -> {:error, :face_detection_failed}
    end
  rescue
    _ -> {:error, :face_detection_failed}
  end

  defp faces(rows) do
    for [left, top, width, height | rest] <- Nx.to_list(rows) do
      %{box: {left, top, width, height}, score: List.last(rest), landmarks: Enum.drop(rest, -1)}
    end
  end

  @doc """
  The feature vector of one face, aligned by its landmarks.

  ## Parameters
    - image: the image the face was detected in
    - face: a face from `detect/1`

  ## Returns
    - `{:ok, features}` (`Evision.Mat.t()`)
    - `{:error, :face_models_unavailable | :face_detection_failed}`
  """
  @spec features(Evision.Mat.t(), face()) :: {:ok, Evision.Mat.t()} | {:error, atom()}
  def features(image, face) do
    with :ok <- check_models() do
      Limiter.run(AikeVision.Processes, fn -> run_features(image, face) end, :infinity)
    end
  end

  defp run_features(image, %{box: {left, top, width, height}, score: score, landmarks: marks}) do
    recognizer = recognizer()

    row =
      Nx.tensor([[left, top, width, height] ++ marks ++ [score]], type: :f32)
      |> Evision.Mat.from_nx()

    aligned = Evision.FaceRecognizerSF.alignCrop(recognizer, image, row)
    {:ok, Evision.FaceRecognizerSF.feature(recognizer, aligned)}
  rescue
    _ -> {:error, :face_detection_failed}
  end

  @doc """
  Cosine similarity of two feature vectors, from 0 (different) to 1 (same face).

  ## Parameters
    - first: features from `features/2`
    - second: features from `features/2`

  ## Returns
    - the similarity; negative values become 0
  """
  @spec similarity(Evision.Mat.t(), Evision.Mat.t()) :: float()
  def similarity(first, second) do
    recognizer()
    |> Evision.FaceRecognizerSF.match(first, second, dis_type: 0)
    |> max(0.0)
  end

  defp recognizer, do: Evision.FaceRecognizerSF.create(model(@recognizer), "")

  defp check_models do
    if available?(), do: :ok, else: {:error, :face_models_unavailable}
  end

  defp model(name), do: Path.join(Application.fetch_env!(:aike_vision, :face_models_dir), name)
end
