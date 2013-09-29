module AFMotion
  class Client
    class << self
      attr_accessor :shared

      # Returns an instance of AFHTTPRequestOperationManager
      def build(base_url, &block)
        operation_manager = AFHTTPRequestOperationManager.alloc.initWithBaseURL(base_url.to_url)
        if block
          dsl = AFMotion::ClientDSL.new(operation_manager)
          dsl.instance_eval(&block)
        end
        if !operation_manager.operationQueue
          operation_manager.operationQueue = NSOperationQueue.mainQueue
        end
        operation_manager
      end

      # Sets AFMotion::Client.shared as the built client
      def build_shared(base_url, &block)
        self.shared = self.build(base_url, &block)
      end
    end
  end
end

module AFMotion
  class ClientDSL
    def initialize(operation_manager)
      @operation_manager = WeakRef.new(operation_manager)
    end

    def header(header, value)
      @operation_manager.headers[header] = value
    end

    def authorization(options = {})
      @operation_manager.requestSerializer.authorization = options
    end

    def operation_queue(operation_queue)
      @operation_manager.operationQueue operation_queue
    end

    OPERATION_TO_REQUEST_SERIALIZER = {
      json: AFJSONRequestSerializer,
      plist: AFPropertyListRequestSerializer
    }
    def request_serializer(serializer)
      if serializer.is_a?(Symbol) || serializer.is_a?(String)
        @operation_manager.requestSerializer = OPERATION_TO_REQUEST_SERIALIZER[serializer.to_sym].serializer
      else
        @operation_manager.requestSerializer = serializer
      end
    end

    OPERATION_TO_RESPONSE_SERIALIZER = {
      json: AFJSONResponseSerializer,
      xml: AFXMLParserResponseSerializer,
      plist: AFPropertyListResponseSerializer,
      image: AFImageResponseSerializer
    }
    def response_serializer(serializer)
      if serializer.is_a?(Symbol) || serializer.is_a?(String)
        @operation_manager.responseSerializer = OPERATION_TO_RESPONSE_SERIALIZER[serializer.to_sym].serializer
      else
        @operation_manager.responseSerializer = serializer
      end
    end
  end
end

class AFHTTPRequestOperationManager
  AFMotion::HTTP_METHODS.each do |method|
    # EX client.get('my/resource.json')
    define_method "#{method}", -> (path, parameters = {}, &callback) do
      create_operation(method, path, parameters, &callback)
    end
  end

  def multipart_post(path, parameters = {}, &callback)
    create_multipart_operation(path, parameters, &callback)
  end

  def create_multipart_operation(path, parameters = {}, &callback)
    inner_callback = Proc.new do |result, form_data,  bytes_written_now,  total_bytes_written, total_bytes_expect|
      case callback.arity
      when 1
        callback.call(result)
      when 2
        callback.call(result, form_data)
      when 3
        progress = nil
        if total_bytes_written && total_bytes_expect
          progress = total_bytes_written.to_f / total_bytes_expect.to_f
        else
          callback.call(result, form_data, progress)
        end
      when 5
        callback.call(result, form_data, bytes_written_now, total_bytes_written, total_bytes_expect)
      end
    end

    multipart_callback = callback.arity == 1 ? nil : lambda { |formData|
      inner_callback.call(nil, formData)
    }
    upload_callback = callback.arity > 2 ? lambda { |bytes_written_now, total_bytes_written, total_bytes_expect|
      inner_callback.call(nil, nil, bytes_written_now, total_bytes_written, total_bytes_expect)
    } : nil

    operation = self.POST(path, parameters: parameters, constructingBodyWithBlock: multipart_callback,
      success: lambda {|operation, responseObject|
        result = AFMotion::HTTPResult.new(operation, responseObject, nil)
        inner_callback.call(result)
      }, failure: lambda {|operation, error|
        result = AFMotion::HTTPResult.new(operation, nil, error)
        inner_callback.call(result)
      })
    if upload_callback
      operation.setUploadProgressBlock(upload_callback)
    end
    operation
  end

  def create_operation(http_method, path, parameters = {}, &callback)
    method_signature = "#{http_method.upcase}:parameters:success:failure:"
    method = self.method(method_signature)
    operation = method.call(path, parameters, AFMotion::Operation.success_block(callback), AFMotion::Operation.failure_block(callback))
  end

  def headers
    requestSerializer.headers
  end

  def all_headers
    requestSerializer.HTTPRequestHeaders
  end

  def authorization=(authorization)
    requestSerializer.authorization = authorization
  end

  private
  # To force RubyMotion pre-compilation of these methods
  def dummy
    self.GET("", parameters: nil, success: nil, failure: nil)
    self.HEAD("", parameters: nil, success: nil, failure: nil)
    self.POST("", parameters: nil, success: nil, failure: nil)
    self.POST("", parameters: nil, constructingBodyWithBlock: nil, success: nil, failure: nil)
    self.PUT("", parameters: nil, success: nil, failure: nil)
    self.DELETE("", parameters: nil, success: nil, failure: nil)
    self.PATCH("", parameters: nil, success: nil, failure: nil)
  end
end