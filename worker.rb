#!/usr/bin/env ruby

require 'pg'
require 'yaml'
require 'securerandom'

secrets = YAML.load_file('secrets.yml')
config = YAML.load_file('config.yml')
rows = Array.new
ansible_vars = Hash.new

def run_every(seconds)
    last_tick = Time.now
    loop do
      sleep 0.1
      if Time.now - last_tick >= seconds
        last_tick += seconds
        yield
      end
    end
end

begin

    conn = PG.connect :dbname => config['database'], :user => secrets['username'], 
           :password => secrets['password']
    
    puts "Successfully logged on to PostgreSQL database #{conn.db} as PostgreSQL user #{conn.user}!"
    puts "Looking for new rows with state #{config["state"]} every #{config["seek_interval"]} seconds"
    run_every(5) do
        res = conn.exec("SELECT * FROM \"#{config["table"]}\" WHERE status = 'pending'")
        res.each do |row|
            if ! rows.include? row
                rows.push(row)
                puts "Found new pending VM!"
                puts "Name: #{row["name"]}"
                puts "MAC: #{row["mac"]}"
                puts "Sleeping for 90 seconds before deploying to #{mac}"
                sleep 90
                puts "Cleaning up old provisions"
                File.unlink("provision.yml")
                puts "Writing new provision config"
                ip = row["ip"]
                gw = ip.split(".")[0...-1].join(".") + ".1"
                ansible_vars["ip"] = ip
                ansible_vars["gw"] = gw
                File.open('provision.yml', "w") do |f| 
                    f.puts(ansible_vars.to_yaml)
                end
                system("ansible-playbook -i hosts set_new_ip.yml")
                if $?.exitstatus == 0
                    puts "Provsioned VM #{row["name"]}"
                else
                    puts "Failed to provision VM. Requeuing..."
                    conn.exec("UPDATE #{config["table"]} SET mac = NULL, status = 'ready_for_provision' WHERE id = #{row["id"]}")
                    rows.delete(row)
                    File.unlink("provision.yml")
                    puts "Rolled back changes on row ##{row["id"]}"
                end
                
            end
        end
    end

rescue PG::Error => e

    puts e.message 
    
ensure

    conn.close if conn

end