module ImageRepHelper

  IS_WIN = Sketchup.platform == :platform_win

  def self.colors_to_image_rep(width, height, colors)
    row_padding = 0
    bits_per_pixel = 32
    pixel_data = self.colors_to_32bit_bytes(colors)
    image_rep = Sketchup::ImageRep.new
    image_rep.set_data(width, height, bits_per_pixel, row_padding, pixel_data)
    image_rep
  end

  # From C API documentation on SUColorOrder
  #
  # > SketchUpAPI expects the channels to be in different orders on
  # > Windows vs. Mac OS. Bitmap data is exposed in BGRA and RGBA byte
  # > orders on Windows and Mac OS, respectively.
  def self.color_to_32bit(color)
    r, g, b, a = color.to_a
    IS_WIN ? [b, g, r, a] : [r, g, b, a]
  end

  def self.colors_to_32bit_bytes(colors)
    colors.map { |color| self.color_to_32bit(color) }.flatten.pack('C*')
  end

  def self.color_to_24bit(color)
    self.color_to_32bit(color)[0, 3]
  end

  def self.colors_to_24bit_bytes(colors)
    colors.map { |color| self.color_to_24bit(color) }.flatten.pack('C*')
  end

end # module


module ImageEffects

  def self.chromatic_abberation(image_rep, offsets)
    colors = image_rep.colors

    ro, go, bo = offsets

    w = image_rep.width
    h = image_rep.height

    w_max = w - 1
    h_max = h - 1

    clamp = lambda { |a, x, b| [a, x, b].sort[1] }

    # p [colors.size, w, h]

    new_colors = colors.each_with_index.map { |color, i|
      x = i % w
      y = i / w
      row_i = y * w

      # p [i, x, y, ri]

      ri = row_i + clamp.call(0, x + ro, w_max)
      gi = row_i + clamp.call(0, x + go, w_max)
      bi = row_i + clamp.call(0, x + bo, w_max)

      # p [ri, gi, bi]

      begin
        r = colors[ri].red
        g = colors[gi].green
        b = colors[bi].blue
        a = color.alpha

        Sketchup::Color.new(r, g, b, a)
      rescue
        p [colors.size, w, h]
        p [i, x, y, ri]
        p [ri, gi, bi]
        raise
      end
    }

    ImageRepHelper.colors_to_image_rep(image_rep.width, image_rep.height, new_colors)
  end

end


module Example

  # Example.apply_effect(red: 2, blue: -2)
  def self.apply_effect(red: 0, green: 0, blue: 0)
    model = Sketchup.active_model
    selection = model.selection
    materials = model.materials

    offsets = [red, green, blue]

    image = selection.grep(Sketchup::Image).first or raise 'Select an Image'
    face = selection.grep(Sketchup::Face).first or raise 'Select a Face'

    definition = model.definitions.find { |definition|
      definition.instances.include?(image)
    }
    image_material = definition.entities.grep(Sketchup::Face).first.material
    image_texture = image_material.texture

    original = image_material.texture.image_rep
    processed = ImageEffects.chromatic_abberation(original, offsets)


    material = materials['ImageEffect'] || materials.add('ImageEffect')
    material.texture = processed
    # material.texture.size = [image_texture.width, image_texture.height]

    # face.material = material
    vs = face.outer_loop.vertices.map(&:position)
    mapping = [
      vs[0],
      Geom::Point3d.new(0, 0, 0),

      vs[1],
      Geom::Point3d.new(1, 0, 0),

      vs[2],
      Geom::Point3d.new(1, 1, 0),

      vs[3],
      Geom::Point3d.new(0, 1, 0),
    ]
    face.position_material(material, mapping, true)
  end

end