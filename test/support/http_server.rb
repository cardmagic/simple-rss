require "socket"

module HTTPServer
  def wait_for_disconnect(client)
    client.read
  rescue Errno::ECONNRESET
    nil
  end

  def with_server(responses)
    server = TCPServer.new("127.0.0.1", 0)
    base_url = "http://127.0.0.1:#{server.addr[1]}"
    requests = []
    worker = Thread.new do
      responses.each do |response|
        client = server.accept
        begin
          request = []
          while (line = client.gets)
            break if line == "\r\n"

            request << line.strip
          end
          requests << request
          if response.respond_to?(:call)
            response.call(client, request)
            next
          end
          status, headers, body = response
          response_headers = headers.merge("Content-Length" => body.bytesize.to_s, "Connection" => "close")
          client.write("HTTP/1.1 #{status} Test\r\n" + response_headers.map { |name, value| "#{name}: #{value}\r\n" }.join + "\r\n" + body)
        ensure
          client.close
        end
      end
    end
    yield base_url, requests
    worker.value
  ensure
    worker&.kill
    worker&.join
    server&.close
  end
end
