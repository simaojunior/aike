defmodule DocumentOcr.OCR.Fake do
  @behaviour DocumentOcr.OCR.Engine
  @impl true
  def extract(_image, _opts) do
    {:ok,
     %{
       "text" => [
         %{"text" => "MARIA DA SILVA", "confidence" => 0.99},
         %{"text" => "529.982.247-25", "confidence" => 0.98},
         %{"text" => "12/03/1990", "confidence" => 0.97}
       ]
     }}
  end
end
