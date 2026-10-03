#!/usr/bin/env ruby

IS_PRODUCTION = ENV['PRODUCTION'] == '1'

if IS_PRODUCTION
	require_relative 'tire'
else
	require_relative 'tire_mock'
end

require 'lerobot-dataset-ruby'

dataset_path = ARGV[0] || ENV['DATASET_PATH']
episode_index = Integer(ARGV[1] || ENV.fetch('EPISODE_INDEX', '0'))

if dataset_path.nil?
	warn "使い方: ruby player.rb DATASET_PATH [EPISODE_INDEX]"
	exit 1
end

reader = Lerobot::Dataset::Ruby::Reader.new(dataset_path)
fps = 10.0
raise ArgumentError, 'fps は 0 より大きくなければなりません' unless fps.positive?
log_interval = [fps.to_i, 1].max

machine = Tire.new

begin
	episode = reader.episode(episode_index)
	puts "エピソード #{episode_index} を再生します（#{episode[:length]} フレーム）"

	playback_started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

	episode[:frames].each_with_index do |frame, frame_index|
		frame_deadline = playback_started_at + (frame_index / fps)
		sleep_time = frame_deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
		sleep(sleep_time) if sleep_time.positive?

		action = Array(frame.fetch(:action))
		raise ArgumentError, "フレーム #{frame_index} の action が不正です" unless action.length >= 2

		left_value = Float(action[0])
		right_value = Float(action[1])
		machine.left_tire(left_value)
		machine.right_tire(right_value)

		puts "フレーム #{frame_index}: 左=#{left_value}, 右=#{right_value}" if frame_index % 30 == 0
		puts sleep_time if frame_index % 30 == 0
		
	end
ensure
	machine&.stop
	machine&.termination
end

puts '再生終了'
