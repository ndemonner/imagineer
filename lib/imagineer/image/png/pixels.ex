defmodule Imagineer.Image.PNG.Pixels do
  alias Imagineer.Image.PNG
  alias PNG.Pixels

  def extract(%PNG{interlace_method: 0}=image) do
    pixels = Pixels.NoInterlace.extract(image)
    Map.put(image, :pixels, pixels)
  end

  def extract(%PNG{interlace_method: 1}=image) do
    pixels = Pixels.Adam7.extract(image)
    Map.put(image, :pixels, pixels)
  end

  def extract(%PNG{interlace_method: interlace_method}) do
    raise "Could not extract pixels from unsupported interlace method #{interlace_method}"
  end

  @doc """
  Splits pixels into unfiltered rows, which can later be filtered.
  """
  def encode(%PNG{interlace_method: 0}=image) do
    %PNG{image | unfiltered_rows: Pixels.NoInterlace.encode(image)}
  end

  def encode(%PNG{interlace_method: interlace_method}) do
    raise "Could not encode unsupported interlace method #{interlace_method}"
  end
end
