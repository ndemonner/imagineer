defmodule Imagineer.Image.PNG.Pixels.NoInterlace do
  alias Imagineer.Image.PNG
  import PNG.Helpers, only: [channels_per_pixel: 1]

  @single_null_bit  <<0::1>>
  @double_null_bits <<0::1, 0::1>>
  @triple_null_bits <<0::1, 0::1, 0::1>>
  @quad_null_bits   <<0::1, 0::1, 0::1, 0::1>>
  @quint_null_bits  <<0::1, 0::1, 0::1, 0::1, 0::1>>
  @hex_null_bits    <<0::1, 0::1, 0::1, 0::1, 0::1, 0::1>>
  @sept_null_bits   <<0::1, 0::1, 0::1, 0::1, 0::1, 0::1, 0::1>>

  @doc """
  Extracts the pixels from all of the unfiltered rows. Sets the `pixels` field
  on the image and returns it.

  ## Example
      iex> alias Imagineer.Image.PNG
      iex> image = %PNG{
      ...>  color_format: :rgb8,
      ...>  bit_depth: 8,
      ...>  interlace_method: 0,
      ...>  width: 2,
      ...>  height: 5,
      ...>  unfiltered_rows: [
      ...>    <<127, 138, 255, 147, 159, 106>>,
      ...>    <<233, 1, 77, 78, 191, 144>>,
      ...>    <<234, 78, 93, 56, 169, 42>>,
      ...>    <<184, 162, 144, 6, 26, 96>>,
      ...>    <<32, 206, 231, 39, 117, 76>>
      ...>  ]
      ...> }
      iex> PNG.Pixels.extract(image).pixels
      [
        [ {127, 138, 255}, {147, 159, 106} ],
        [ {233, 1, 77}, {78, 191, 144} ],
        [ {234, 78, 93}, {56, 169, 42} ],
        [ {184, 162, 144}, {6, 26, 96} ],
        [ {32, 206, 231}, {39, 117, 76} ]
      ]

  """
  def extract(%PNG{unfiltered_rows: unfiltered_rows}=image) do
    extract_pixels(unfiltered_rows, image)
  end

  def extract_pixels(rows, %PNG{color_format: color_format, bit_depth: bit_depth, width: width}) do
    extract_pixels(rows, width, channels_per_pixel(color_format), bit_depth, [])
  end

  defp extract_pixels([], _width, _channels_per_pixel, _bit_depth, pixel_rows) do
    Enum.reverse(pixel_rows)
  end

  defp extract_pixels([row | unfiltered_rows], width, channels_per_pixel, bit_depth, pixel_rows) do
    pixel_row = extract_pixels_from_row(row, width, channels_per_pixel, bit_depth)
    extract_pixels(unfiltered_rows, width, channels_per_pixel, bit_depth, [pixel_row | pixel_rows])
  end

  defp extract_pixels_from_row(row, width, channels_per_pixel, bit_depth) do
    pixel_size = channels_per_pixel * bit_depth
    extract_pixels_from_row(row, width, channels_per_pixel, bit_depth, pixel_size, [])
  end

  # In the base case, we have pulled everything from the row and are left with
  # a reversed list of pixels. It is possible that `row` is larger than the number
  # of pixels because some pixels (e.g. 1 bit grayscale) do not always fill an
  # entire byte.
  defp extract_pixels_from_row(_row, 0, _channels_per_pixel, _bit_depth, _pixel_size, pixels) do
    Enum.reverse pixels
  end

  defp extract_pixels_from_row(row, width, channels_per_pixel, bit_depth, pixel_size, pixels) do
    <<pixel_bits::bits-size(pixel_size), rest_of_row::bits>> = row
    pixel = extract_pixel(pixel_bits, bit_depth, channels_per_pixel)
    extract_pixels_from_row(rest_of_row, width - 1, channels_per_pixel, bit_depth, pixel_size, [pixel | pixels])
  end

  def extract_pixel(pixel_bits, bit_depth, channels_per_pixel) do
    extract_pixel(pixel_bits, bit_depth, [], channels_per_pixel)
  end

  # In the base case, we have no more channels to parse and we are done!
  defp extract_pixel(<<>>, _bit_depth, channel_list, 0) do
    List.to_tuple Enum.reverse channel_list
  end

  defp extract_pixel(pixel_bits, bit_depth, channel_list, channels) do
    remaining_channels = channels - 1
    rest_size = bit_depth * remaining_channels
    <<channel::integer-size(bit_depth), rest::bits-size(rest_size)>> = pixel_bits
    extract_pixel(rest, bit_depth, [channel | channel_list], remaining_channels)
  end

  @doc """
  Encodes each row of pixels into a scanline. For no interlace, that really just
  means putting all of the channels for a row into a binary.
  """
  def encode(%PNG{pixels: pixels}=image) do
    encode_pixel_rows(pixels, image)
  end

  defp encode_pixel_rows(pixels, image) do
    encode_pixel_rows(pixels, image, [])
  end

  # In the base case, we are out of pixel rows and are finished!
  defp encode_pixel_rows([], _image, unfiltered_rows) do
    Enum.reverse unfiltered_rows
  end

  defp encode_pixel_rows([pixel_row | rest_rows], image, unfiltered_rows) do
    encoded_row = encode_pixel_row(pixel_row, image, <<>>)
    new_unfiltered_rows = [encoded_row | unfiltered_rows]
    encode_pixel_rows(rest_rows, image, new_unfiltered_rows)
  end

  defp encode_pixel_row([], _image, encoded_pixels) do
    encoded_pixels
  end

  defp encode_pixel_row([pixel | rest_pixels], image, encoded_pixels) do
    new_encoded_pixels = encoded_pixels <> encode_pixel(pixel, image)
    encode_pixel_row(rest_pixels, image, new_encoded_pixels)
  end

  # Pixels are translated to bytes, sized based on the bit depth of the PNG.
  # If this leaves an incomplete byte (e.g. :grayscale1), fill the rest with
  # 0s.
  defp encode_pixel(pixel, image) do
    encoded_bits = encode_pixel_bits(pixel, image.bit_depth)
    # Pad the end of the bits so we have bytes
    case rem(bit_size(encoded_bits), 8) do
      0 -> encoded_bits
      1 -> encoded_bits <> @sept_null_bits
      2 -> encoded_bits <> @hex_null_bits
      3 -> encoded_bits <> @quint_null_bits
      4 -> encoded_bits <> @quad_null_bits
      5 -> encoded_bits <> @triple_null_bits
      6 -> encoded_bits <> @double_null_bits
      7 -> encoded_bits <> @single_null_bit
    end
  end

  # Single channel pixel (e.g. grayscale)
  defp encode_pixel_bits({one}, bit_depth) do
    <<one::integer-size(bit_depth)>>
  end
# {:ok, png} = Imagineer.load("./test/support/images/png/baby_octopus.png")
  # Two channel pixel (e.g. grayscale + alpha)
  defp encode_pixel_bits({one, two}, bit_depth) do
    <<one::integer-size(bit_depth), two::integer-size(bit_depth)>>
  end

  # three channel pixel (e.g. rgb)
  defp encode_pixel_bits({one, two, three}, bit_depth) do
    <<
      one::integer-size(bit_depth),
      two::integer-size(bit_depth),
      three::integer-size(bit_depth)
    >>
  end

  # four channel pixel (e.g. rgb + alpha)
  defp encode_pixel_bits({one, two, three, four}, bit_depth) do
    <<
      one::integer-size(bit_depth),
      two::integer-size(bit_depth),
      three::integer-size(bit_depth),
      four::integer-size(bit_depth)
    >>
  end
end
