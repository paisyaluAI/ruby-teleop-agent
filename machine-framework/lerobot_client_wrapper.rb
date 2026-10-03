require 'net/http'
require 'uri'
require 'json'
require 'base64'

module LeRobot
  # ============================================================================
  # VLAAsyncClient: HTTP非同期推論クライアント
  # ============================================================================
  class VLAAsyncClient
    DEFAULT_SERVER_URL = ENV.fetch('INFERENCE_SERVER_URL', 'http://127.0.0.1:8080')
    DEFAULT_PROMPT = ENV.fetch('PROMPT', 'Go to the blue star')

    attr_reader :server_url, :prompt, :connected

    def initialize(server_url: DEFAULT_SERVER_URL, prompt: DEFAULT_PROMPT, create_steps: 10, exec_steps: 10)
      url = server_url.sub(%r{\Aws://}, 'http://').sub(%r{\Awss://}, 'https://')
      @uri = URI.parse(url)
      @server_url = url
      @prompt = prompt
      @create_steps = create_steps.to_i
      @exec_steps = exec_steps.to_i

      @action_queue = []
      @queue_mutex = Mutex.new

      @latest_obs = nil
      @obs_mutex = Mutex.new

      @running = false
      @worker_thread = nil
      @connected = false
    end

    def connect(timeout: 5)
      return true if @connected

      puts "[VLAAsyncClient] 接続確認中: #{@server_url}"
      res = Net::HTTP.start(@uri.host, @uri.port, open_timeout: timeout, read_timeout: timeout) do |http|
        http.get('/health')
      end

      unless res.is_a?(Net::HTTPSuccess)
        warn "[VLAAsyncClient] 接続失敗 (Status: #{res.code})"
        return false
      end

      @connected = true
      @running = true

      @is_fetching = false

      # バックグラウンドワーカースレッド: キュー残が1以下になったら最新観測で推論を行い末尾に追加
      @worker_thread = Thread.new do
        while @running
          should_fetch = false
          @queue_mutex.synchronize do
            should_fetch = (@action_queue.size <= 1) && !@is_fetching
          end

          obs = nil
          if should_fetch
            @obs_mutex.synchronize { obs = @latest_obs }
          end

          if obs && obs[:image_bytes]
            @queue_mutex.synchronize { @is_fetching = true }
            begin
              request_inference(obs)
            ensure
              @queue_mutex.synchronize { @is_fetching = false }
            end
          end
          sleep 0.02
        end
      end

      puts "[VLAAsyncClient] 接続完了"
      true
    rescue StandardError => e
      warn "[VLAAsyncClient] 接続エラー: #{e.message}"
      @connected = false
      false
    end

    # ノンブロッキングで次のアクション [left, right] を取得 (キューが空なら nil)
    def next_action(image_bytes, state, task = @prompt)
      if image_bytes && !image_bytes.empty?
        @obs_mutex.synchronize do
          @latest_obs = {
            image_bytes: image_bytes,
            state: Array(state).map(&:to_f),
            task: task || @prompt
          }
        end
      end

      @queue_mutex.synchronize do
        @action_queue.shift
      end
    end

    def queue_size
      @queue_mutex.synchronize { @action_queue.size }
    end

    def stop
      @running = false
      @worker_thread&.kill
      @worker_thread = nil
      @connected = false
    end

    private

    def request_inference(obs)
      payload = {
        image: Base64.strict_encode64(obs[:image_bytes]),
        state: obs[:state],
        task: obs[:task] || @prompt,
        create_steps: @create_steps,
        exec_steps: @exec_steps
      }

      req = Net::HTTP::Post.new('/predict', { 'Content-Type' => 'application/json' })
      req.body = JSON.generate(payload)

      res = Net::HTTP.start(@uri.host, @uri.port, open_timeout: 5, read_timeout: 10) do |http|
        http.request(req)
      end

      if res.is_a?(Net::HTTPSuccess)
        data = JSON.parse(res.body)
        chunk = data['action_chunk'] || data['full_action_chunk']
        if chunk.is_a?(Array) && !chunk.empty?
          exec_chunk = chunk.first(@exec_steps)
          new_actions = exec_chunk.map { |a| [a[0].to_f, a[1].to_f] }
          @queue_mutex.synchronize do
            @action_queue.concat(new_actions)
          end
        end
      end
    rescue StandardError => e
      warn "[VLAAsyncClient] 推論リクエスト失敗: #{e.message}"
    end
  end

  # 後方互換性エイリアス
  VLAClient = VLAAsyncClient
end
