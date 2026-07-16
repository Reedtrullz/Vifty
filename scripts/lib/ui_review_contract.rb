require "json"
require "digest"
require "zlib"

module ViftyUIReview
  SCHEMA_VERSION = 3
  REQUIRED_FIXTURE_CONSTRUCTIONS = %w[
    daemon-client
    hardware
    helper-installer
    login-item
    notification-center
    power-client
  ].freeze
  REQUIRED_FIXTURE_READ_OPERATIONS = %w[
    agent-status
    daemon-ping
    fan-control-ownership
    hardware-snapshot
    login-item-status
    notification-authorization
    power
    thermal-pressure
  ].freeze
  OPTIONAL_FIXTURE_READ_OPERATIONS = %w[codex-usage].freeze
  MAX_PNG_FILE_BYTES = 96 * 1024 * 1024
  MAX_PNG_PIXELS = 21_600_000
  MAX_PNG_IDAT_CHUNKS = 4_096
  PNG_INFLATE_INPUT_CHUNK_BYTES = 4 * 1024
  PNG_BYTES_PER_PIXEL = {
    0 => 1,
    2 => 3,
    4 => 2,
    6 => 4
  }.freeze

  class PNGError < StandardError; end

  def self.fixture_recorder_errors(recorder)
    return ["recorder is missing"] unless recorder.is_a?(Hash)

    errors = []
    %w[attemptedHardwareCommands attemptedExternalMutations realControlPathConstructions].each do |key|
      errors << "#{key} must be empty" unless recorder[key] == []
    end
    constructions = recorder["fixtureConstructions"]
    unless constructions.is_a?(Array) && constructions.all? { |item| item.is_a?(String) } &&
           constructions.sort == REQUIRED_FIXTURE_CONSTRUCTIONS
      errors << "fixtureConstructions do not match the inert fixture contract"
    end
    reads = recorder["readOperations"]
    if !reads.is_a?(Array) || !reads.all? { |item| item.is_a?(String) }
      errors << "readOperations must be an array of strings"
    else
      observed = reads.uniq.sort
      allowed = (REQUIRED_FIXTURE_READ_OPERATIONS + OPTIONAL_FIXTURE_READ_OPERATIONS).sort
      missing = REQUIRED_FIXTURE_READ_OPERATIONS - observed
      unknown = observed - allowed
      errors << "readOperations are missing the deterministic preparation baseline: #{missing.join(", ")}" unless missing.empty?
      errors << "readOperations contain unknown fixture reads: #{unknown.join(", ")}" unless unknown.empty?
    end
    errors
  end

  def self.deep_freeze(value)
    case value
    when Hash
      value.each do |key, item|
        deep_freeze(key)
        deep_freeze(item)
      end
    when Array
      value.each { |item| deep_freeze(item) }
    end
    value.freeze
  end

  def self.request(
    state:,
    surface:,
    window:,
    appearance: "light",
    contrast: "standard",
    interaction: "none",
    text_size: "standard",
    transparency: "standard"
  )
    {
      "appearance" => appearance,
      "contrast" => contrast,
      "interaction" => interaction,
      "state" => state,
      "surface" => surface,
      "textSize" => text_size,
      "transparency" => transparency,
      "window" => window
    }
  end

  REQUEST_KEYS = deep_freeze(%w[
    appearance
    contrast
    interaction
    state
    surface
    textSize
    transparency
    window
  ])

  STATES = deep_freeze(%w[
    healthy-auto
    divergent-per-fan-curve-draft
    active-manual
    recovery-mixed-ownership
    helper-blocked
    notification-denied
    edited-profile
    selected-vs-highest-temperature
    raw-spike-telemetry
  ])

  EXPECTED_FIXTURE_REQUESTS = deep_freeze({
    "healthy-auto" => request(
      state: "healthy-auto", surface: "main", window: "1180x820"
    ),
    "divergent-per-fan-curve-draft" => request(
      state: "divergent-per-fan-curve-draft", surface: "main", window: "1180x820"
    ),
    "active-manual" => request(
      state: "active-manual", surface: "main", window: "1180x820"
    ),
    "recovery-mixed-ownership" => request(
      state: "recovery-mixed-ownership", surface: "main", window: "1180x820"
    ),
    "helper-blocked" => request(
      state: "helper-blocked", surface: "main", window: "1180x820"
    ),
    "notification-denied" => request(
      state: "notification-denied", surface: "main", window: "1180x820"
    ),
    "edited-profile" => request(
      state: "edited-profile", surface: "main", window: "1180x820"
    ),
    "selected-vs-highest-temperature" => request(
      state: "selected-vs-highest-temperature", surface: "main", window: "1180x820"
    ),
    "raw-spike-telemetry" => request(
      state: "raw-spike-telemetry", surface: "main", window: "1180x820"
    )
  })

  EXPECTED_VISUAL_REQUESTS = deep_freeze({
    "main-780x480-light" => request(
      state: "healthy-auto", surface: "main", window: "780x480"
    ),
    "main-780x480-dark" => request(
      state: "healthy-auto", surface: "main", window: "780x480", appearance: "dark"
    ),
    "main-1180x820-light" => request(
      state: "healthy-auto", surface: "main", window: "1180x820"
    ),
    "main-1180x820-dark" => request(
      state: "healthy-auto", surface: "main", window: "1180x820", appearance: "dark"
    ),
    "main-1280x720-light" => request(
      state: "healthy-auto", surface: "main", window: "1280x720"
    ),
    "main-1280x720-dark" => request(
      state: "healthy-auto", surface: "main", window: "1280x720", appearance: "dark"
    ),
    "main-1500x900-light" => request(
      state: "healthy-auto", surface: "main", window: "1500x900"
    ),
    "main-1500x900-dark" => request(
      state: "healthy-auto", surface: "main", window: "1500x900", appearance: "dark"
    ),
    "state-divergent-per-fan-curve-draft" => request(
      state: "divergent-per-fan-curve-draft", surface: "main", window: "1180x820"
    ),
    "state-active-manual" => request(
      state: "active-manual", surface: "main", window: "1180x820"
    ),
    "state-recovery-mixed-ownership" => request(
      state: "recovery-mixed-ownership", surface: "main", window: "1180x820"
    ),
    "state-helper-blocked" => request(
      state: "helper-blocked", surface: "main", window: "1180x820"
    ),
    "state-notification-denied" => request(
      state: "notification-denied", surface: "settings-notifications", window: "native"
    ),
    "state-edited-profile" => request(
      state: "edited-profile", surface: "main", window: "1180x820"
    ),
    "state-selected-vs-highest-temperature" => request(
      state: "selected-vs-highest-temperature", surface: "main", window: "1180x820"
    ),
    "state-raw-spike-telemetry" => request(
      state: "raw-spike-telemetry", surface: "main", window: "1180x820"
    ),
    "settings-general" => request(
      state: "healthy-auto", surface: "settings-general", window: "native"
    ),
    "settings-menu-bar" => request(
      state: "healthy-auto", surface: "settings-menu-bar", window: "native"
    ),
    "settings-notifications" => request(
      state: "healthy-auto", surface: "settings-notifications", window: "native"
    ),
    "settings-agent-workflows" => request(
      state: "healthy-auto", surface: "settings-agent-workflows", window: "native"
    ),
    "menu-popover" => request(
      state: "healthy-auto", surface: "menu-popover", window: "320xauto"
    ),
    "main-increase-contrast" => request(
      state: "healthy-auto",
      surface: "main",
      window: "1180x820",
      contrast: "increased",
      transparency: "reduced"
    ),
    "main-reduce-transparency" => request(
      state: "healthy-auto", surface: "main", window: "1180x820", transparency: "reduced"
    ),
    "main-accessibility-text" => request(
      state: "healthy-auto", surface: "main", window: "1180x820", text_size: "accessibility"
    ),
    "settings-general-accessibility-text" => request(
      state: "healthy-auto",
      surface: "settings-general",
      window: "native",
      text_size: "accessibility"
    ),
    "settings-menu-bar-accessibility-text" => request(
      state: "healthy-auto",
      surface: "settings-menu-bar",
      window: "native",
      text_size: "accessibility"
    ),
    "settings-notifications-accessibility-text" => request(
      state: "notification-denied",
      surface: "settings-notifications",
      window: "native",
      text_size: "accessibility"
    ),
    "settings-agent-workflows-accessibility-text" => request(
      state: "healthy-auto",
      surface: "settings-agent-workflows",
      window: "native",
      text_size: "accessibility"
    )
  })

  EXPECTED_AX_REQUESTS = deep_freeze({
    "confirmed-owner-headline" => request(
      state: "active-manual", surface: "main", window: "1180x820"
    ),
    "correct-per-fan-target" => request(
      state: "divergent-per-fan-curve-draft", surface: "main", window: "1180x820"
    ),
    "six-adjustable-point-controls" => request(
      state: "divergent-per-fan-curve-draft", surface: "main", window: "1180x820"
    ),
    "sensor-selected-trait-value" => request(
      state: "selected-vs-highest-temperature", surface: "main", window: "1180x820"
    ),
    "explicit-temperature-role" => request(
      state: "selected-vs-highest-temperature", surface: "main", window: "1180x820"
    ),
    "notification-actions" => request(
      state: "notification-denied", surface: "settings-notifications", window: "native"
    ),
    "settings-logical-traversal" => request(
      state: "healthy-auto", surface: "settings-general", window: "native"
    ),
    "no-duplicate-chart-elements" => request(
      state: "divergent-per-fan-curve-draft", surface: "main", window: "1180x820"
    ),
    "compact-main-scroll-reachable" => request(
      state: "healthy-auto",
      surface: "main",
      window: "780x480",
      interaction: "structural-scroll",
      text_size: "accessibility"
    ),
    "settings-general-scroll-reachable" => request(
      state: "healthy-auto",
      surface: "settings-general",
      window: "native",
      interaction: "structural-scroll",
      text_size: "accessibility"
    ),
    "settings-menu-bar-scroll-reachable" => request(
      state: "healthy-auto",
      surface: "settings-menu-bar",
      window: "native",
      interaction: "structural-scroll",
      text_size: "accessibility"
    ),
    "settings-notifications-scroll-reachable" => request(
      state: "notification-denied",
      surface: "settings-notifications",
      window: "native",
      interaction: "structural-scroll",
      text_size: "accessibility"
    ),
    "settings-agent-workflows-scroll-reachable" => request(
      state: "healthy-auto",
      surface: "settings-agent-workflows",
      window: "native",
      interaction: "structural-scroll",
      text_size: "accessibility"
    )
  })

  ATTESTATION_REVIEWER_PLACEHOLDER = "REPLACE_WITH_REVIEWER_NAME".freeze
  ATTESTATION_REVIEWED_AT_PLACEHOLDER = "1970-01-01T00:00:00Z".freeze
  ATTESTATION_OBSERVATION_PLACEHOLDER_PREFIX = "REPLACE_WITH_OBSERVED_RESULT:".freeze
  MINIMUM_ATTESTATION_OBSERVATION_LENGTH = 24

  VOICEOVER_SAFE_ACTION_SEQUENCE = deep_freeze(%w[
    settings-general
    settings-menu-bar
    settings-notifications
    settings-agent-workflows
    settings-general
  ])
  VOICEOVER_INSPECT_ONLY_CONTROLS = deep_freeze(%w[
    curve-point-adjustables
    notification-actions
    sensor-buttons
  ])
  VOICEOVER_STEP_ROW_IDS = deep_freeze({
    "spoken-labels-values" => %w[
      confirmed-owner-headline
      correct-per-fan-target
      explicit-temperature-role
      no-duplicate-chart-elements
      notification-actions
      sensor-selected-trait-value
      settings-logical-traversal
      six-adjustable-point-controls
    ],
    "focus-movement" => %w[
      no-duplicate-chart-elements
      notification-actions
      sensor-selected-trait-value
      settings-logical-traversal
      six-adjustable-point-controls
    ],
    "rotor-grouping" => %w[
      confirmed-owner-headline
      no-duplicate-chart-elements
      settings-logical-traversal
    ],
    "adjustable-controls" => %w[
      six-adjustable-point-controls
    ],
    "buttons" => %w[
      notification-actions
      sensor-selected-trait-value
      settings-logical-traversal
    ],
    "scroll-reachability" => %w[
      compact-main-scroll-reachable
      settings-agent-workflows-scroll-reachable
      settings-general-scroll-reachable
      settings-menu-bar-scroll-reachable
      settings-notifications-scroll-reachable
    ],
    "safe-action-announcements" => %w[
      settings-logical-traversal
    ]
  })

  def self.canonicalize(value)
    case value
    when Hash
      value.keys.sort.to_h { |key| [key, canonicalize(value.fetch(key))] }
    when Array
      value.map { |item| canonicalize(item) }
    else
      value
    end
  end

  def self.canonical_json(value)
    JSON.generate(canonicalize(value))
  end

  def self.sha256_json(value)
    Digest::SHA256.hexdigest(canonical_json(value))
  end

  def self.expected_fixture_requests
    EXPECTED_FIXTURE_REQUESTS
  end

  def self.expected_visual_requests
    EXPECTED_VISUAL_REQUESTS
  end

  def self.expected_ax_requests
    EXPECTED_AX_REQUESTS
  end

  def self.expected_container_kind(request)
    case request.fetch("surface")
    when "main"
      "main-window"
    when "menu-popover"
      "popover"
    when /\Asettings-/
      "settings-window"
    else
      raise ArgumentError, "Unsupported UI review surface: #{request.fetch("surface")}"
    end
  end

  def self.expected_provenance(request)
    case request.fetch("surface")
    when "main"
      "swiftui-main-window"
    when "menu-popover"
      "ns-popover-status-item"
    when /\Asettings-/
      "swiftui-settings-scene"
    else
      raise ArgumentError, "Unsupported UI review surface: #{request.fetch("surface")}"
    end
  end

  def self.expected_geometry(request)
    window = request.fetch("window")
    case window
    when "native"
      [nil, nil]
    when "320xauto"
      [320, nil]
    else
      match = /\A([1-9]\d*)x([1-9]\d*)\z/.match(window)
      raise ArgumentError, "Unsupported UI review window: #{window}" unless match

      [match[1].to_i, match[2].to_i]
    end
  end

  def self.analyze_png(path, expected_width:, expected_height:)
    size = File.size(path)
    raise PNGError, "PNG file exceeds the bounded size limit" if size > MAX_PNG_FILE_BYTES

    analyze_png_bytes(
      File.binread(path),
      expected_width: expected_width,
      expected_height: expected_height
    )
  rescue Errno::ENOENT => error
    raise PNGError, "PNG file is missing: #{error.message}"
  rescue SystemCallError => error
    raise PNGError, "PNG file cannot be read: #{error.message}"
  end

  def self.analyze_png_bytes(data, expected_width:, expected_height:)
    unless expected_width.is_a?(Integer) && expected_width.positive? &&
           expected_height.is_a?(Integer) && expected_height.positive?
      raise PNGError, "PNG expected dimensions are invalid"
    end
    expected_pixels = expected_width * expected_height
    if expected_pixels > MAX_PNG_PIXELS
      raise PNGError, "PNG expected dimensions exceed the bounded pixel limit"
    end
    unless data.is_a?(String) && data.bytesize <= MAX_PNG_FILE_BYTES
      raise PNGError, "PNG file exceeds the bounded size limit"
    end

    parsed = parse_png(data)
    unless parsed.fetch(:width) == expected_width && parsed.fetch(:height) == expected_height
      raise PNGError, "PNG pixel dimensions do not match observed NSWindow content size and scale"
    end

    decoded = decode_png_scanlines(parsed)
    raise PNGError, "PNG has no visible pixels" if decoded.fetch(:visible_pixels).zero?
    if decoded.fetch(:unique_visible_colors) < 2
      raise PNGError, "PNG has fewer than two visible colors"
    end
    parsed.slice(:width, :height).merge(decoded)
  end

  def self.parse_png(data)
    signature = "\x89PNG\r\n\x1a\n".b
    raise PNGError, "file is not a PNG" unless data.start_with?(signature)

    offset = signature.bytesize
    chunk_index = 0
    ihdr = nil
    idat = +"".b
    saw_idat = false
    idat_finished = false
    saw_iend = false
    saw_plte = false
    idat_chunk_count = 0
    while offset < data.bytesize
      raise PNGError, "PNG has a truncated chunk header" if data.bytesize - offset < 12

      length = data.byteslice(offset, 4).unpack1("N")
      type = data.byteslice(offset + 4, 4)
      unless type && type.bytesize == 4 && type.bytes.all? { |byte| (65..90).cover?(byte) || (97..122).cover?(byte) }
        raise PNGError, "PNG chunk type is invalid"
      end
      unless (type.getbyte(2) & 0x20).zero?
        raise PNGError, "PNG chunk type uses the reserved lowercase bit"
      end
      chunk_end = offset + 12 + length
      raise PNGError, "PNG has a truncated #{type.inspect} chunk" if chunk_end > data.bytesize

      payload = data.byteslice(offset + 8, length)
      recorded_crc = data.byteslice(offset + 8 + length, 4).unpack1("N")
      unless recorded_crc == Zlib.crc32(type + payload)
        raise PNGError, "PNG #{type} checksum mismatch"
      end
      if chunk_index.zero? && type != "IHDR"
        raise PNGError, "PNG IHDR must be the first chunk"
      end

      case type
      when "IHDR"
        raise PNGError, "PNG contains duplicate IHDR chunks" if ihdr
        raise PNGError, "PNG IHDR must be the first chunk" unless chunk_index.zero?
        raise PNGError, "PNG IHDR length is invalid" unless length == 13

        width, height, bit_depth, color_type, compression, filter, interlace = payload.unpack("NNCCCCC")
        raise PNGError, "PNG dimensions must be positive" unless width.positive? && height.positive?
        raise PNGError, "PNG dimensions exceed the bounded pixel limit" if width * height > MAX_PNG_PIXELS
        raise PNGError, "PNG must use 8-bit samples" unless bit_depth == 8
        raise PNGError, "PNG color type is unsupported" unless PNG_BYTES_PER_PIXEL.key?(color_type)
        raise PNGError, "PNG compression method is invalid" unless compression.zero?
        raise PNGError, "PNG filter method is invalid" unless filter.zero?
        raise PNGError, "PNG must be non-interlaced" unless interlace.zero?
        ihdr = {
          width: width,
          height: height,
          bit_depth: bit_depth,
          color_type: color_type
        }
      when "PLTE"
        raise PNGError, "PNG PLTE appears before IHDR" unless ihdr
        raise PNGError, "PNG contains duplicate PLTE chunks" if saw_plte
        raise PNGError, "PNG PLTE must precede IDAT" if saw_idat
        unless [2, 6].include?(ihdr.fetch(:color_type)) && length.positive? && length <= 768 && (length % 3).zero?
          raise PNGError, "PNG PLTE is invalid for the selected color type"
        end
        saw_plte = true
      when "IDAT"
        raise PNGError, "PNG IDAT appears before IHDR" unless ihdr
        raise PNGError, "PNG IDAT chunks must be contiguous" if idat_finished
        raise PNGError, "PNG contains an empty IDAT payload" if length.zero? && !saw_idat
        if idat.bytesize + length > MAX_PNG_FILE_BYTES
          raise PNGError, "PNG IDAT exceeds the bounded size limit"
        end
        idat_chunk_count += 1
        if idat_chunk_count > MAX_PNG_IDAT_CHUNKS
          raise PNGError, "PNG contains too many IDAT chunks"
        end
        idat << payload
        saw_idat = true
      when "IEND"
        raise PNGError, "PNG IEND appears before IDAT" unless saw_idat
        raise PNGError, "PNG IEND length is invalid" unless length.zero?
        saw_iend = true
        offset = chunk_end
        break
      when "tRNS"
        raise PNGError, "PNG tRNS transparency is unsupported"
      else
        if type.getbyte(0) & 0x20 == 0
          raise PNGError, "PNG contains unsupported critical chunk #{type}"
        end
        idat_finished = true if saw_idat
      end
      offset = chunk_end
      chunk_index += 1
    end

    raise PNGError, "PNG has no IHDR chunk" unless ihdr
    raise PNGError, "PNG has no IDAT payload" unless saw_idat && !idat.empty?
    raise PNGError, "PNG has no IEND chunk" unless saw_iend
    raise PNGError, "PNG contains trailing data after IEND" unless offset == data.bytesize
    ihdr.merge(idat: idat)
  end

  def self.decode_png_scanlines(parsed)
    width = parsed.fetch(:width)
    height = parsed.fetch(:height)
    color_type = parsed.fetch(:color_type)
    bytes_per_pixel = PNG_BYTES_PER_PIXEL.fetch(color_type)
    row_bytes = width * bytes_per_pixel
    expected_bytes = height * (row_bytes + 1)
    inflated = inflate_png_idat(parsed.fetch(:idat), expected_bytes)
    previous = "\0".b * row_bytes
    digest = Digest::SHA256.new
    visible_pixels = 0
    visible_colors = []
    last_sample_row = nil
    last_canonical_row = nil
    last_visible_pixels = 0
    last_visible_colors = []
    offset = 0

    height.times do |row_index|
      filter_type = inflated.getbyte(offset)
      unless filter_type && filter_type.between?(0, 4)
        raise PNGError, "PNG scanline #{row_index} filter type is invalid"
      end
      offset += 1
      filtered = inflated.byteslice(offset, row_bytes)
      offset += row_bytes
      if filter_type.zero?
        current = filtered
      else
        current = "\0".b * row_bytes
        row_bytes.times do |index|
          left = index >= bytes_per_pixel ? current.getbyte(index - bytes_per_pixel) : 0
          up = previous.getbyte(index)
          upper_left = index >= bytes_per_pixel ? previous.getbyte(index - bytes_per_pixel) : 0
          predictor = case filter_type
                      when 1 then left
                      when 2 then up
                      when 3 then (left + up) / 2
                      when 4 then paeth_predictor(left, up, upper_left)
                      end
          current.setbyte(index, (filtered.getbyte(index) + predictor) & 0xff)
        end
      end

      if last_sample_row == current
        canonical_row = last_canonical_row
        row_visible_pixels = last_visible_pixels
        row_visible_colors = last_visible_colors
      else
        canonical_row = +"".b
        row_visible_pixels = 0
        row_visible_colors = []
        pixel_offset = 0
        width.times do
          red, green, blue, alpha = canonical_rgba(current, pixel_offset, color_type)
          pixel_offset += bytes_per_pixel
          if alpha.zero?
            red = green = blue = 0
          else
            row_visible_pixels += 1
            if row_visible_colors.length < 2
              color = (red << 24) | (green << 16) | (blue << 8) | alpha
              row_visible_colors << color unless row_visible_colors.include?(color)
            end
          end
          canonical_row << red << green << blue << alpha
        end
        last_sample_row = current
        last_canonical_row = canonical_row
        last_visible_pixels = row_visible_pixels
        last_visible_colors = row_visible_colors
      end
      digest.update(canonical_row)
      visible_pixels += row_visible_pixels
      row_visible_colors.each do |color|
        visible_colors << color if visible_colors.length < 2 && !visible_colors.include?(color)
      end
      previous = current
    end

    {
      canonical_pixel_sha256: digest.hexdigest,
      visible_pixels: visible_pixels,
      unique_visible_colors: visible_colors.length
    }
  end

  def self.inflate_png_idat(idat, expected_bytes)
    inflater = Zlib::Inflate.new
    inflated = +"".b
    offset = 0
    begin
      while offset < idat.bytesize
        chunk = idat.byteslice(offset, PNG_INFLATE_INPUT_CHUNK_BYTES)
        inflated << inflater.inflate(chunk)
        offset += chunk.bytesize
        if inflated.bytesize > expected_bytes
          raise PNGError, "PNG decompressed scanline length mismatch"
        end
        if inflater.finished?
          unless inflater.total_in == idat.bytesize && offset == idat.bytesize
            raise PNGError, "PNG IDAT contains trailing compressed data"
          end
          break
        end
      end
      unless inflater.finished?
        tail = inflater.finish
        if inflated.bytesize + tail.bytesize > expected_bytes
          raise PNGError, "PNG decompressed scanline length mismatch"
        end
        inflated << tail
      end
      unless inflater.finished? && inflater.total_in == idat.bytesize
        raise PNGError, "PNG IDAT stream did not terminate exactly"
      end
    rescue Zlib::Error => error
      raise PNGError, "PNG IDAT cannot be decompressed: #{error.message}"
    ensure
      inflater.close rescue nil
    end
    unless inflated.bytesize == expected_bytes
      raise PNGError, "PNG decompressed scanline length mismatch"
    end
    inflated
  end

  def self.canonical_rgba(row, offset, color_type)
    case color_type
    when 0
      gray = row.getbyte(offset)
      [gray, gray, gray, 255]
    when 2
      [row.getbyte(offset), row.getbyte(offset + 1), row.getbyte(offset + 2), 255]
    when 4
      gray = row.getbyte(offset)
      [gray, gray, gray, row.getbyte(offset + 1)]
    when 6
      [
        row.getbyte(offset),
        row.getbyte(offset + 1),
        row.getbyte(offset + 2),
        row.getbyte(offset + 3)
      ]
    end
  end

  def self.paeth_predictor(left, up, upper_left)
    estimate = left + up - upper_left
    left_distance = (estimate - left).abs
    up_distance = (estimate - up).abs
    upper_left_distance = (estimate - upper_left).abs
    return left if left_distance <= up_distance && left_distance <= upper_left_distance

    up_distance <= upper_left_distance ? up : upper_left
  end

  private_class_method :deep_freeze,
                       :request,
                       :parse_png,
                       :decode_png_scanlines,
                       :inflate_png_idat,
                       :canonical_rgba,
                       :paeth_predictor
end
