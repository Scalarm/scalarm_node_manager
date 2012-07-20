module Scalarm

  class NodeManagerNotifier

    def initialize(sleep_time, node_manager_port, sis_url, sis_login, sis_pass)
      @sleep_time = sleep_time
      @node_manager_port = node_manager_port
      @sis_url, @sis_login, @sis_pass = sis_url, sis_login, sis_pass
    end

    def register
      # checking current
      puts "#{Time.now} --- Register itself into the Information Service"
      host = ""
      UDPSocket.open { |s| s.connect('64.233.187.99', 1); host = s.addr.last }

      sis_server, sis_port = @sis_url.split(":")
      http = Net::HTTP.new(sis_server, sis_port.to_i)

      req = Net::HTTP::Post.new("/register_node_manager")
      req.basic_auth @sis_login, @sis_pass
      req.set_form_data({"server" => host, "port" => @node_manager_port})

      begin
        response = http.request(req)
      rescue Exception => e
        puts "Exception occured but nothin terrible :) - #{e.message}"
      end
    end

    def start_registration_thread
      Thread.new do
        while true do
          register
          sleep @sleep_time
        end
      end
    end

  end

end