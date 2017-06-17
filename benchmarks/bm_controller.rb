require_relative './benchmarking_support'
require_relative './app'
require_relative './setup'

class NullLogger < Logger
  def initialize(*args)
  end

  def add(*args, &block)
  end
end

class BenchmarkApp < Rails::Application
  routes.append do
    get '/simple' => 'main#simple'
    get '/text' => 'main#text'

    get '/serialize_to_string' => 'main#serialize_to_string'
    get '/serialize_to_stream' => 'streaming#serialize_to_stream'
  end

  config.secret_token = 's'*30
  config.secret_key_base = 'foo'
  config.consider_all_requests_local = false

  # simulate production
  config.cache_classes = true
  config.eager_load = true
  config.action_controller.perform_caching = true

  # otherwise deadlock occured
  config.middleware.delete 'Rack::Lock'

  # to disable log files
  config.logger = NullLogger.new
  config.active_support.deprecation = :log
end

BenchmarkApp.initialize!

class AuthorFastSerializer < Panko::Serializer
  attributes :id, :name
end

class PostWithHasOneFastSerializer < Panko::Serializer
  attributes :id, :body, :title, :author_id

  has_one :author, serializer: AuthorFastSerializer
end

class StreamingController < ActionController::Base
  include ActionController::Live

  def serialize_to_stream
    headers['Content-Type'.freeze] = 'application/json'.freeze

    data = Benchmark.data[:all]
    serializer = Panko::ArraySerializer.new([], each_serializer: PostWithHasOneFastSerializer)
    writer = Oj::StreamWriter.new(response.stream, mode: :rails)

    serializer.serialize_to_writer(data, writer)

    response.stream.close
  end
end

class MainController < ActionController::Base
  def text
    render text: '{"ok":true}'.freeze, content_type: 'application/json'.freeze
  end

  def simple
    render json: { ok: true }
  end

  def serialize_to_string
    data = Benchmark.data[:all]
    serializer = Panko::ArraySerializer.new([], each_serializer: PostWithHasOneFastSerializer)
    writer = Oj::StringWriter.new(mode: :rails)

    serializer.serialize_to_writer(data, writer)

    render text: writer.to_s, content_type: 'application/json'.freeze
  end
end

class RouteNotFoundError < StandardError;end


def request(method, path)
  response = Rack::MockRequest.new(BenchmarkApp).send(method, path)
  if response.status.in?([404, 500])
    raise RouteNotFoundError.new, 'not found #{method.to_s.upcase} #{path}'
  end
  response
end


Benchmark.ams('text') { request(:get, '/text') }
Benchmark.ams('simple') { request(:get, '/simple') }

Benchmark.ams('serialize_to_string') { request(:get, '/serialize_to_string') }
Benchmark.ams('serialize_to_stream') { request(:get, '/serialize_to_stream') }
