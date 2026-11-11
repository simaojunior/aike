face_models? =
  case Application.get_env(:aike_vision, :face_models_dir) do
    nil ->
      false

    directory ->
      Enum.all?(
        ["face_detection_yunet_2023mar.onnx", "face_recognition_sface_2021dec.onnx"],
        &File.regular?(Path.join(directory, &1))
      )
  end

ExUnit.start(exclude: if(face_models?, do: [], else: [:face_models]))
