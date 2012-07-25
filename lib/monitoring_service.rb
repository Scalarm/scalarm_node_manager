require "mongo"

module Scalarm
  TIME_FORMAT = "%Y-%m-%d %H:%M:%S"

  class MonitoringService

    def initialize(config)
      @config = config

      @host = ""
      UDPSocket.open { |s| s.connect('64.233.187.99', 1); @host = s.addr.last }
      @host.gsub!("\.", "_")

      monitoring_db_url = @config["monitoring_db_url"]
      port = 27017
      if monitoring_db_url.split(":").size == 2
        monitoring_db_url, port = monitoring_db_url.split(":")
      end

      @monitoring_db = Mongo::Connection.new(monitoring_db_url, port).db(@config["monitoring_db_name"])
      @auth = true
      if @config.has_key?("monitoring_db_user")
        begin
          @auth = @monitoring_db.authenticate(@config["monitoring_db_user"], @config["monitoring_db_pass"])
        rescue Mongo::AuthenticationError => e
          @auth = false
          puts "Authentication failed"
        end
      end

      @monitoring_parameters = @config["monitored_metrics"].split(":")
      @experiment_manager_log_last_bytes = {}
    end

    def start_monitoring_thread
      Thread.new do
        while true
          monitor
          sleep(@config["monitoring_interval"].to_i)
        end
      end
    end

    def monitor
      measurements = []

      @monitoring_parameters.each do |metric_type|
        measurements += self.send("monitor_#{metric_type}")
      end

      send_measurements(measurements)
    end

    def send_measurements(measurements)
      if not @auth
        puts "Could not send measurements due to failed authentication"
        return
      end

      last_inserted_values = {}

      measurements.each do |measurement_table|
        table_name = "#{@host}.#{measurement_table[0]}"
        table = @monitoring_db[table_name]

        last_value = nil
        if not last_inserted_values.has_key?(table_name) or last_inserted_values[table_name].nil?
          last_value = table.find_one({}, { :sort => [ [ "date", "desc" ] ]})
        else
          last_value = last_inserted_values[table_name]
        end

        doc = {"date" => measurement_table[1], "value" => measurement_table[2]}

        # puts "Last inserted value: #{last_value}"

        if not last_value.nil?

          last_date = if last_value["date"].class.name == "String" then
                        DateTime.strptime(last_value["date"], Scalarm::TIME_FORMAT).to_time
                      else
                        last_value["date"]
                      end

          current_date = DateTime.strptime(doc["date"], Scalarm::TIME_FORMAT).to_time

          next if last_date > current_date
        end

        puts "Measurement of #{measurement_table[0]} : #{doc}"
        table.insert(doc)
        last_inserted_values[table_name] = doc
      end

    end

    # monitors percantage utilization of the CPU
    def monitor_cpu
      mpstat_out = `mpstat`
      mpstat_lines = mpstat_out.split("\n")
      cpu_util_values = mpstat_lines[-1].split

      cpu_idle = cpu_util_values[-1].to_f
      cpu_util = 100.0 - cpu_idle

      [ [ "System___NULL___CPU", Time.now.strftime(Scalarm::TIME_FORMAT), cpu_util.to_i.to_s] ]
    end

    # monitoring free memory in the system
    def monitor_memory
      mem_lines = `free -m`
      mem_line = mem_lines.split("\n")[1].split
      free_mem = mem_line[3]

      [ [ "System___NULL___Mem", Time.now.strftime(Scalarm::TIME_FORMAT), free_mem ] ]
    end

    # monitors various metric related to block devices utilization
    def monitor_storage
      storage_measurements = []

      iostat_out = `iostat -d -m`
      iostat_out_lines = iostat_out.split("\n")

      iostat_out_lines.each_with_index do |iostat_out_line, i|
        if iostat_out_line.start_with?("Device:")

          storage_metric_names = iostat_out_line.split(" ")
          1.upto(2) do |k|
            if not iostat_out_lines[i+k].nil?
              storage_metric_values = iostat_out_lines[i+k].split(" ")
              device_name = storage_metric_values[storage_metric_names.index("Device:")]

              ["MB_read", "MB_wrtn"].each do |metric_name|
                storage_measurements << ["Storage___#{device_name}___#{metric_name}",
                                         Time.now.strftime(Scalarm::TIME_FORMAT),
                                         storage_metric_values[storage_metric_names.index(metric_name)]]
              end

            end
          end

        end
      end

      storage_measurements
    end

    def monitor_experiment_manager
      log_dir = File.join(@config["installation_dir"], "scalarm_experiment_manager", "log")
      return [] if not File.exist?(log_dir)

      measurements = []
      Dir.open(log_dir).each do |original_filename|
        filename = original_filename.split(".")[0]
        next if not original_filename.end_with?(".log") or filename.split("_") == 1 # not a log file

        port = filename.split("_")[1]
        last_byte = @experiment_manager_log_last_bytes.has_key?(port) ? @experiment_manager_log_last_bytes[port] : 0

        log_file = File.open(File.join(log_dir, original_filename), "r")
        log_file.seek(last_byte, IO::SEEK_SET)

        request_measurements, bytes_counter = parse_manager_log_file(log_file.readlines, port)
        #measurements += calculate_avg_within_seconds(request_measurements)
        measurements += request_measurements

        @experiment_manager_log_last_bytes[port] = last_byte + bytes_counter
      end

      measurements
    end

    private

    def parse_manager_log_file(new_lines, port)
      request_measurements, bytes_counter = [], 0
      is_request_parsing = false; request_method = ""; request_date = ""; temp_byte_counter = 0

      new_lines.each do |log_line|
        temp_byte_counter += log_line.size

        if not is_request_parsing and log_line.start_with?("Started")
          request_method = (log_line.split(" ")[2][2..-2]).split("/")[0..1].join("_").split("?")[0]
          request_date = log_line.split(" ")[-3] + " " + log_line.split(" ")[-2]
          is_request_parsing = true
        elsif is_request_parsing and log_line.start_with?("Completed")
          response_time = log_line.split(" ")[4]

          is_request_parsing = false

          if response_time.end_with?("ms")
            request_measurements << [ "ExperimentManager___#{port}___#{request_method}",
                                      request_date, response_time[0..-2].to_i ]

            bytes_counter += temp_byte_counter
            temp_byte_counter = 0
            #puts "Date: #{request_date} --- Method: #{request_method} --- Response time: #{response_time}"
          end
        end
      end

      return request_measurements, bytes_counter
    end

    def calculate_avg_within_seconds(request_measurements)
      avg_request_measurements = {}

      request_measurements.each do |method_name, tab_of_measurements|
        avg_measurements = {}
        tab_of_measurements.each do |time_and_value|
          avg_measurements[time_and_value[0]] = [] if not avg_measurements[time_and_value[0]]
          avg_measurements[time_and_value[0]] << time_and_value[1]
        end

        avg_tab_of_measurements = []
        avg_measurements.each do |timestamp, measurements|
          measurement_sum = measurements.reduce(0) { |sum, element| sum += element.to_i }
          avg_tab_of_measurements << [Time.parse(timestamp), (measurement_sum/measurements.size).to_i]
        end

        avg_request_measurements[method_name] = avg_tab_of_measurements.sort { |a, b| a[0] <=> b[0] }

        puts "Method: #{method_name} --- Size: #{avg_tab_of_measurements.size} --- Measurements: #{avg_tab_of_measurements.join(",")}"
      end

      avg_request_measurements
    end

  end

end
