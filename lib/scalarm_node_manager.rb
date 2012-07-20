require "scalarm_node_manager/version"
require "node_manager_notifier"
require "sinatra"
require "yaml"
require 'net/http'

module Scalarm

  class ScalarmNodeManager

    def initialize
      spec = Gem::Specification.find_by_name("scalarm_node_manager")
      @config = YAML::load_file File.join(spec.gem_dir, "etc", "config.yaml")

      @@manager_type = nil

      node_manager_notifier = Scalarm::NodeManagerNotifier.new(@config["registration_interval"].to_i,
                                                               @config["starting_port"],
                                                               @config["scalarm_information_service_url"],
                                                               @config["information_service_login"],
                                                               @config["information_service_password"])

      node_manager_notifier.start_registration_thread
    end

    def server_port
      @config["port"].to_i
    end

    def install(manager_type)
      return if not ['experiment', 'storage', 'simulation'].include?(manager_type)

      @@manager_type = manager_type

      sis_server, sis_port = @config["scalarm_information_service_url"].split(":")

      http = Net::HTTP.new(sis_server, sis_port.to_i)
      req = Net::HTTP::Get.new("/download_#{@@manager_type}_manager")

      req.basic_auth @config["information_service_login"], @config["information_service_password"]
      response = http.request(req)

      output_destination = File.join(@config["installation_dir"], "manager.zip")
      open(output_destination, "wb") do |file|
        file.write(response.body)
      end

      @@component_dir = "#{@config["installation_dir"]}/scalarm_#{@@manager_type}_manager"
      `rm -rf #{@@component_dir}` if File.exist?(@@component_dir)

      # unzipping file
      `cd #{@config["installation_dir"]}; unzip manager.zip; rm manager.zip;`
      # dependency install
      `cd #{@@component_dir}; bundle install`
    end

    def start_manager(manager_type, number)
      if manager_type == "experiment"
        `cd #{component_dir(manager_type)}; #{experiment_manager_cmd("start", @config["starting_port"], number)}`
      end
    end

    def stop_manager(manager_type, number)
      if manager_type == "experiment"
        `cd #{component_dir(manager_type)}; #{experiment_manager_cmd("stop", @config["starting_port"], number)}`
      end
    end

    def manager_status(manager_type, number)
      if manager_type == "experiment"
        `cd #{component_dir(manager_type)}; #{experiment_manager_cmd("status", @config["starting_port"], number)}`
      end
    end

    def credentials
      [@config["login"], @config["password"]]
    end

    private

    def experiment_manager_cmd(type, port, number)
      "ruby scalarm_experiment_manager.rb #{type} #{port} #{number}"
    end

    def component_dir(manager_type)
      "#{@config["installation_dir"]}/scalarm_#{manager_type}_manager"
    end

  end

end

snm = Scalarm::ScalarmNodeManager.new

use Rack::Auth::Basic, "Restricted Area" do |username, password|
  [username, password] == snm.credentials
end

set :port, snm.server_port
enable :run

# web interface
get '/install_manager/:manager_type' do
  snm.install(params[:manager_type])
end

get '/update_manager' do

end

get '/start_manager/:manager_type/:number' do
  snm.start_manager(params[:manager_type], params[:number])
end

get '/stop_manager/:manager_type/:number' do
  snm.stop_manager(params[:manager_type], params[:number])
end

get '/manager_status/:manager_type/:number' do
  snm.manager_status(params[:manager_type], params[:number])
end
