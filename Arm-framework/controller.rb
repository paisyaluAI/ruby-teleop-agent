# frozen_string_literal: true

require 'io/console'

# ==============================================================================
# SO-101 / 多関節ロボットアーム (Feetech STS3215 シリアルバスサーボ) 制御 & キーボード入力
# - ライブラリ側 (Lerobot-Dataset-Ruby) は純粋な N 次元 Reader/Writer のみとし、
#   アーム固有のシリアルサーボ通信・キーボード制御は本ファイルに集約。
# ==============================================================================
module SO101
  DEFAULT_DOF = 6

  MOTOR_NAMES = %w[
    shoulder_pan
    shoulder_lift
    elbow_flex
    wrist_flex
    wrist_roll
    gripper
  ].freeze

  FEATURE_NAMES = MOTOR_NAMES.map { |name| "#{name}.pos" }.freeze

  HEADER = [0xFF, 0xFF].freeze
  INST_PING = 0x01
  INST_READ = 0x02
  INST_WRITE = 0x03
  INST_SYNC_WRITE = 0x83

  ADDR_TORQUE_ENABLE = 40
  ADDR_GOAL_POSITION = 42
  ADDR_PRESENT_POSITION = 56

  RAW_RESOLUTION = 4096
  RAW_CENTER = 2048

  def self.resolve_motors(dof: nil, motors: nil)
    if motors.is_a?(Hash) && !motors.empty?
      names = motors.keys.map(&:to_s)
      ids = motors.transform_keys(&:to_s).transform_values(&:to_i)
      return [names, ids]
    elsif motors.is_a?(Array) && !motors.empty?
      names = motors.map { |m| m.to_s.sub(/\.pos\z/, '') }
      ids = names.each_with_index.to_h { |name, i| [name, i + 1] }
      return [names, ids]
    end

    target_dof = (dof || DEFAULT_DOF).to_i
    raise ArgumentError, "dof は 1 以上の整数を指定してください (指定値: #{dof.inspect})" if target_dof < 1

    names = if target_dof == DEFAULT_DOF
              MOTOR_NAMES.dup
            else
              (1..target_dof).map { |i| "joint_#{i}" }
            end
    ids = names.each_with_index.to_h { |name, i| [name, i + 1] }
    [names, ids]
  end

  # Feetech STS3215 シリアル通信バス
  class FeetechBus
    attr_reader :port, :baudrate, :mock, :positions, :motor_names, :motor_ids, :dof

    def initialize(port:, baudrate: 1_000_000, mock: false, norm_mode: :range_m100_100, dof: nil, motors: nil)
      @port = port
      @baudrate = baudrate
      @mock = mock
      @norm_mode = norm_mode
      @io = nil
      @mutex = Mutex.new

      @motor_names, @motor_ids = SO101.resolve_motors(dof: dof, motors: motors)
      @dof = @motor_names.size
      @positions = Array.new(@dof, 0.0)
    end

    def configure_dimensions(dof: nil, motors: nil)
      @motor_names, @motor_ids = SO101.resolve_motors(dof: dof, motors: motors)
      @dof = @motor_names.size
      @positions = Array.new(@dof, 0.0)
    end

    def connect
      return true if @mock

      unless File.exist?(@port)
        raise Errno::ENOENT, "SO101 シリアルポートが見つかりません: #{@port}"
      end

      system('stty', '-F', @port, @baudrate.to_s, 'raw', '-echo', '-echoe', '-echok', 'cs8', '-cstopb', '-parenb')
      @io = File.open(@port, File::RDWR | File::NOCTTY | File::NONBLOCK)
      @io.sync = true
      true
    end

    def disconnect
      @mutex.synchronize do
        @io.close if @io && !@io.closed?
        @io = nil
      end
    end

    def scan_motor_ids(max_id: 16)
      return @motor_ids.values if @mock || !@io

      (1..max_id).select { |id| ping(id) }
    end

    def ping(id, timeout: 0.015)
      return true if @mock
      return false unless @io

      @mutex.synchronize do
        clear_rx_buffer
        length = 2
        chk = checksum(id, length, INST_PING, [])
        packet = (HEADER + [id, length, INST_PING, chk]).pack('C*')
        @io.write(packet)

        buf = read_bytes_until(6, timeout)
        bytes = buf.bytes
        (0..(bytes.size - 6)).any? { |i| bytes[i] == 0xFF && bytes[i + 1] == 0xFF && bytes[i + 2] == id }
      end
    rescue IOError, SystemCallError
      false
    end

    def write_torque(enable)
      return true if @mock

      val = enable ? 1 : 0
      @motor_ids.each_value do |id|
        write_register(id, ADDR_TORQUE_ENABLE, [val])
      end
      true
    end

    def read_positions
      return @positions.dup if @mock

      @motor_names.each_with_index.map do |name, idx|
        id = @motor_ids[name]
        raw = read_position_raw(id)
        @positions[idx] = raw ? normalize_position(name, raw) : @positions[idx]
      end
    end

    def write_positions(target_positions)
      values = coerce_positions(target_positions)
      @positions = values.dup
      return @positions if @mock

      params = [ADDR_GOAL_POSITION, 2]
      @motor_names.each_with_index do |name, idx|
        id = @motor_ids[name]
        raw = unnormalize_position(name, values[idx])
        params << id << (raw & 0xFF) << ((raw >> 8) & 0xFF)
      end
      send_packet(0xFE, INST_SYNC_WRITE, params)
      @positions
    end

    def coerce_positions(input)
      if input.is_a?(Hash)
        @motor_names.map do |name|
          val = input[name] || input[name.to_sym] || input["#{name}.pos"] || input[:"#{name}.pos"] || 0.0
          clamp_joint(name, val.to_f)
        end
      else
        arr = Array(input).map(&:to_f)
        @motor_names.each_with_index.map do |name, idx|
          clamp_joint(name, arr.fetch(idx, 0.0))
        end
      end
    end

    def clamp_joint(name, val)
      if @norm_mode == :unit
        name == 'gripper' ? val.clamp(0.0, 1.0) : val.clamp(-1.0, 1.0)
      else
        name == 'gripper' ? val.clamp(0.0, 100.0) : val.clamp(-100.0, 100.0)
      end
    end

    private

    def normalize_position(name, raw)
      raw_clamped = raw.to_i.clamp(0, RAW_RESOLUTION - 1)
      if @norm_mode == :unit
        if name == 'gripper'
          (raw_clamped.to_f / (RAW_RESOLUTION - 1)).round(4)
        else
          (((raw_clamped - RAW_CENTER).to_f / RAW_CENTER)).clamp(-1.0, 1.0).round(4)
        end
      elsif name == 'gripper'
        ((raw_clamped.to_f / (RAW_RESOLUTION - 1)) * 100.0).round(2)
      else
        (((raw_clamped - RAW_CENTER).to_f / RAW_CENTER) * 100.0).clamp(-100.0, 100.0).round(2)
      end
    end

    def unnormalize_position(name, norm_val)
      val = clamp_joint(name, norm_val.to_f)
      raw = if @norm_mode == :unit
              if name == 'gripper'
                (val * (RAW_RESOLUTION - 1)).round
              else
                (RAW_CENTER + val * RAW_CENTER).round
              end
            elsif name == 'gripper'
              ((val / 100.0) * (RAW_RESOLUTION - 1)).round
            else
              (RAW_CENTER + (val / 100.0) * RAW_CENTER).round
            end
      raw.clamp(0, RAW_RESOLUTION - 1)
    end

    def checksum(id, length, instruction, params)
      sum = id + length + instruction + params.sum
      (~sum) & 0xFF
    end

    def clear_rx_buffer
      return unless @io

      begin
        @io.read_nonblock(256) while IO.select([@io], nil, nil, 0)
      rescue IO::WaitReadable, EOFError
        # バッファクリア完了
      end
    end

    def read_bytes_until(expected_len, timeout)
      buf = +''
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      while buf.bytesize < expected_len
        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        break if remaining <= 0
        break unless IO.select([@io], nil, nil, remaining)

        begin
          buf << @io.read_nonblock(expected_len - buf.bytesize)
        rescue IO::WaitReadable
          next
        rescue EOFError
          break
        end
      end
      buf
    end

    def send_packet(id, instruction, params)
      return unless @io

      length = params.size + 2
      chk = checksum(id, length, instruction, params)
      packet = (HEADER + [id, length, instruction] + params + [chk]).pack('C*')
      @mutex.synchronize { @io.write(packet) }
    rescue IOError, SystemCallError => e
      warn "[SO101::FeetechBus] 送信エラー: #{e.message}"
    end

    def write_register(id, address, data_bytes)
      send_packet(id, INST_WRITE, [address] + data_bytes)
    end

    def read_position_raw(id, timeout: 0.02)
      return RAW_CENTER unless @io

      @mutex.synchronize do
        clear_rx_buffer
        params = [ADDR_PRESENT_POSITION, 2]
        length = params.size + 2
        chk = checksum(id, length, INST_READ, params)
        packet = (HEADER + [id, length, INST_READ] + params + [chk]).pack('C*')
        @io.write(packet)

        buf = read_bytes_until(8, timeout)
        bytes = buf.bytes
        hdr_idx = (0..(bytes.size - 8)).find { |i| bytes[i] == 0xFF && bytes[i + 1] == 0xFF && bytes[i + 2] == id }
        return nil unless hdr_idx

        low = bytes[hdr_idx + 5]
        high = bytes[hdr_idx + 6]
        raw = (high << 8) | low
        (raw & 0x8000) != 0 ? -(raw & 0x7FFF) : raw
      end
    rescue IOError, SystemCallError
      nil
    end
  end

  # Leader アーム (人間が手で動かすマスター側: トルク OFF で現在角度を読み取る)
  class Leader
    attr_reader :bus

    def initialize(port: ENV.fetch('LEADER_PORT', '/dev/ttyACM0'), baudrate: 1_000_000, mock: false, norm_mode: :range_m100_100, dof: nil, motors: nil)
      @bus = FeetechBus.new(port: port, baudrate: baudrate, mock: mock, norm_mode: norm_mode, dof: dof, motors: motors)
      @bus.connect
      @bus.write_torque(false)
    end

    def dof
      @bus.dof
    end

    def motor_names
      @bus.motor_names
    end

    def read_positions
      @bus.read_positions
    end

    def set_mock_positions(positions)
      @bus.write_positions(positions) if @bus.mock
    end

    def termination
      @bus.write_torque(false)
      @bus.disconnect
    end
  end

  # Follower アーム (Leader に追従して動くスレーブ側: トルク ON で目標角度へ駆動)
  class Follower
    attr_reader :bus

    def initialize(port: ENV.fetch('FOLLOWER_PORT', '/dev/ttyACM1'), baudrate: 1_000_000, mock: false, norm_mode: :range_m100_100, dof: nil, motors: nil)
      @bus = FeetechBus.new(port: port, baudrate: baudrate, mock: mock, norm_mode: norm_mode, dof: dof, motors: motors)
      @bus.connect
      @bus.write_torque(true)
      puts(@bus.mock ? "[SO101 Follower] Mock モードで起動しました (#{@bus.dof}軸)" : "[SO101 Follower] 接続完了 (#{port}, #{@bus.dof}軸)")
    end

    def dof
      @bus.dof
    end

    def motor_names
      @bus.motor_names
    end

    def get_state
      @bus.read_positions
    end

    def send_action(positions)
      @bus.write_positions(positions)
    end

    def stop
      @bus.read_positions
    end

    def termination
      @bus.write_torque(false)
      @bus.disconnect
      puts(@bus.mock ? '[SO101 Follower] Mock 終了' : '[SO101 Follower] トルクを解除して切断しました')
    end
  end
end

# ==============================================================================
# Controller: キーボード操作 (S / Enter / D / Q) + Leader アーム入力
# ==============================================================================
class Controller
  MOCK_STEP = 5.0

  attr_reader :selected_joint, :leader, :dof, :joint_names

  def initialize(mock: ENV['PRODUCTION'] != '1', leader_port: ENV.fetch('LEADER_PORT', '/dev/ttyACM0'), dof: nil, motors: nil)
    @mock = mock
    @leader = SO101::Leader.new(
      port: leader_port,
      mock: @mock,
      dof: dof,
      motors: motors
    )

    # 実機モードかつ dof/motors 未指定の場合、バス上の接続サーボを自動スキャンして軸数を自動適用
    if !@mock && dof.nil? && motors.nil?
      detected_ids = @leader.bus.scan_motor_ids
      if !detected_ids.empty? && detected_ids.size != @leader.dof
        @leader.bus.configure_dimensions(dof: detected_ids.size)
      end
    end

    @dof = @leader.dof
    @joint_names = @leader.motor_names
    @positions = Array.new(@dof, 0.0)
    @selected_joint = 0

    @start_pressed = false
    @stop_pressed = false
    @finish_pressed = false
    @discard_pressed = false

    puts '--------------------------------------------------'
    puts "  [アーム制御ガイド (#{@dof}軸: #{@joint_names.join(', ')})]"
    puts '  [S] キー     : エピソード記録開始'
    puts '  [Enter] キー : エピソード保存 & 一時停止'
    puts '  [D] キー     : エピソード破棄 & 一時停止'
    puts '  [Q] キー     : セッション終了 & 完全保存'
    if @mock
      max_key = [@dof, 9].min
      puts "  [Mock関節操作] [1]〜[#{max_key}] (または [/] キー): 関節選択 / [+][-](↑↓): 角度増減 / [0]: リセット"
    else
      puts "  [Leaderアーム] ポート: #{leader_port} (#{@dof}軸テレオペレーション)"
    end
    puts '--------------------------------------------------'
  end

  def get_action
    if @mock
      @positions.dup
    else
      @positions = @leader.read_positions
      @positions.dup
    end
  end

  alias get_joint_positions get_action

  def poll
    @start_pressed = false
    @stop_pressed = false
    @finish_pressed = false
    @discard_pressed = false

    while (key = read_key_nonblock)
      handle_key(key)
    end
  end

  def process_start
    @start_pressed
  end

  def process_stop
    @stop_pressed
  end

  def process_finish
    @finish_pressed
  end

  def process_discard
    @discard_pressed
  end

  def termination
    @leader&.termination
  end

  private

  def read_key_nonblock
    return nil unless IO.select([$stdin], nil, nil, 0)

    if $stdin.tty?
      $stdin.raw(min: 0, time: 0) do |io|
        ch = io.read_nonblock(1, exception: false)
        return nil if ch.nil? || ch == :wait_readable

        if ch == "\e"
          seq = io.read_nonblock(2, exception: false)
          ch += seq if seq.is_a?(String)
        end
        ch
      end
    else
      ch = $stdin.read_nonblock(1, exception: false)
      ch == :wait_readable ? nil : ch
    end
  rescue EOFError, IOError, Errno::EIO
    nil
  end

  def handle_key(key)
    case key
    when "\u0003" # Ctrl+C
      raise Interrupt
    when 's', 'S'
      @start_pressed = true
    when "\r", "\n" # Enter
      @stop_pressed = true
    when 'd', 'D'
      @discard_pressed = true
    when 'q', 'Q'
      @finish_pressed = true
    when '1'..'9'
      idx = key.to_i - 1
      if idx < @dof
        @selected_joint = idx
        puts "[Mock] 選択関節: [#{@selected_joint + 1}] #{@joint_names[@selected_joint]} (現在値: #{@positions[@selected_joint].round(1)})" if @mock
      end
    when '['
      @selected_joint = (@selected_joint - 1) % @dof
      puts "[Mock] 選択関節: [#{@selected_joint + 1}] #{@joint_names[@selected_joint]} (現在値: #{@positions[@selected_joint].round(1)})" if @mock
    when ']'
      @selected_joint = (@selected_joint + 1) % @dof
      puts "[Mock] 選択関節: [#{@selected_joint + 1}] #{@joint_names[@selected_joint]} (現在値: #{@positions[@selected_joint].round(1)})" if @mock
    when '+', '=', "\e[A", "\e[C"
      adjust_mock_joint(MOCK_STEP) if @mock
    when '-', '_', "\e[B", "\e[D"
      adjust_mock_joint(-MOCK_STEP) if @mock
    when '0'
      if @mock
        @positions.fill(0.0)
        @leader.set_mock_positions(@positions)
        puts '[Mock] 全関節を 0.0 にリセットしました'
      end
    end
  end

  def adjust_mock_joint(delta)
    name = @joint_names[@selected_joint]
    updated = @positions[@selected_joint] + delta
    @positions[@selected_joint] = @leader.bus.clamp_joint(name, updated)
    @leader.set_mock_positions(@positions)
  end
end
